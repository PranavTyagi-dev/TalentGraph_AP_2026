-- TalentGraph | PostgreSQL query catalog
-- Source: Express route modules and Prisma setup scripts. Each entry is an SQL
-- equivalent of a logical DB operation with fictional bound values filled in.
-- Includes are expressed with JOINs; repeated operations share IDs. The API
-- enforces authentication, validation, transitions and transaction boundaries.
-- Run on the isolated fixture from benchmark_fixture.sql after 03_schema.sql.
-- Writes use separate rolled-back transactions for demonstration and timing.
-- Sequence values may advance on rollback. Use only a disposable database.
-- Dates use the fixed benchmark clock 2026-11-17 12:00 UTC. LIMIT 6 is one page.

-- READ R1 | Find a login account by email (also the seed existence check)
-- Source: server/routes/auth.js
SELECT * FROM "User" WHERE email = 'owner@example.test';

-- READ R2 | Resolve the session token and load the signed-in account
-- Source: server/routes/auth.js
SELECT s.token, s."expiresAt", s."userId", u.name, u.email, u.role, u.suspended
FROM "Session" s JOIN "User" u ON u.id = s."userId"
WHERE s.token = 'token-101';

-- READ R3 | Load the account before checking its current password
-- Source: server/routes/auth.js
SELECT * FROM "User" WHERE id = 101;

-- WRITE W1 | Register a candidate and create the linked profile
-- Source: server/routes/auth.js
BEGIN;
WITH account AS (
    INSERT INTO "User" (name,email,role,"passwordHash")
    VALUES ('New Candidate','new@example.test','CANDIDATE','fixture-hash')
    RETURNING *
), profile AS (
    INSERT INTO "Profile" ("userId") SELECT id FROM account
)
SELECT id,name,email,role FROM account;
ROLLBACK;

-- WRITE W2 | Create a recruiter account (also used for admin provisioning)
-- Source: server/routes/auth.js
BEGIN;
INSERT INTO "User" (name,email,role,"passwordHash")
VALUES ('New Recruiter','new@example.test','RECRUITER','fixture-hash')
RETURNING id,name,email,role;
ROLLBACK;

-- WRITE W3 | Create a session after registration or login
-- Source: server/routes/auth.js
BEGIN;
INSERT INTO "Session" (token,"userId","expiresAt")
VALUES ('new-token',101,TIMESTAMP '2026-11-18 12:00') RETURNING *;
ROLLBACK;

-- WRITE W4 | Delete the session on logout
-- Source: server/routes/auth.js
BEGIN;
DELETE FROM "Session" WHERE token='token-101';
ROLLBACK;

-- WRITE W5 | Update the signed-in user’s display name
-- Source: server/routes/auth.js
BEGIN;
UPDATE "User" SET name='Updated Name' WHERE id=101 RETURNING id,name,email,role;
ROLLBACK;

-- WRITE W6 | Replace a password when the previous hash still matches
-- Source: server/routes/auth.js
BEGIN;
UPDATE "User" SET "passwordHash"='replacement-fixture-hash'
WHERE id=101 AND "passwordHash"='fixture-hash' RETURNING id;
ROLLBACK;

-- WRITE W7 | Revoke all sessions on password change or suspension
-- Source: server/routes/auth.js
BEGIN;
DELETE FROM "Session" WHERE "userId"=101;
ROLLBACK;

-- READ R4 | Search published public jobs with company names
-- Source: server/routes/public.js
SELECT j.id,j.title,j.description,j.location,j."requiredSkills",j."workMode",j.compensation,
       j."employmentType",j."experienceLevel",j.deadline,c.id AS company_id,c.name AS company_name
FROM "Job" j JOIN "Company" c ON c.id = j."companyId"
WHERE j."isOpen" AND j.publication = 'Published' AND NOT c.suspended
  AND (j.deadline IS NULL OR j.deadline > TIMESTAMP '2026-11-17 12:00') AND j.title ILIKE '%analyst%'
ORDER BY j.id DESC LIMIT 6 OFFSET 0;

-- READ R5 | Count matching public jobs
-- Source: server/routes/public.js
SELECT COUNT(*) FROM "Job" j JOIN "Company" c ON c.id = j."companyId"
WHERE j."isOpen" AND j.publication = 'Published' AND NOT c.suspended
  AND (j.deadline IS NULL OR j.deadline > TIMESTAMP '2026-11-17 12:00') AND j.title ILIKE '%analyst%';

-- READ R6 | Read one accepting public job
-- Source: server/routes/public.js
SELECT j.id,j.title,j.description,j.location,j."requiredSkills",j."workMode",j.compensation,
       j."employmentType",j."experienceLevel",j.deadline,c.id AS company_id,c.name AS company_name
FROM "Job" j JOIN "Company" c ON c.id = j."companyId"
WHERE j.id=1 AND j."isOpen" AND j.publication = 'Published' AND NOT c.suspended
  AND (j.deadline IS NULL OR j.deadline > TIMESTAMP '2026-11-17 12:00');

-- READ R7 | Read a public company profile
-- Source: server/routes/public.js
SELECT id,name,description FROM "Company" WHERE id=1 AND NOT suspended;

-- READ R8 | List managed companies with members and job totals
-- Source: server/routes/jobs.js
SELECT c.*,
       ARRAY(SELECT jsonb_build_object('id',u.id,'name',u.name,'email',u.email)
             FROM "CompanyMember" m JOIN "User" u ON u.id=m."userId"
             WHERE m."companyId"=c.id) AS members,
       (SELECT COUNT(*) FROM "Job" j WHERE j."companyId"=c.id) AS jobs
FROM "Company" c
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
))
ORDER BY c.name;

-- WRITE W8 | Create a company for its owner
-- Source: server/routes/jobs.js
BEGIN;
INSERT INTO "Company" (name,description,"recruiterId")
VALUES ('New Company','Campus roles',1) RETURNING *;
ROLLBACK;

-- WRITE W9 | Edit an active company as its owner
-- Source: server/routes/jobs.js
BEGIN;
UPDATE "Company" SET name='Updated Company',description='Campus hiring'
WHERE id=1 AND "recruiterId"=1 AND NOT suspended RETURNING *;
ROLLBACK;

-- READ R9 | Find an active recruiter to invite
-- Source: server/routes/jobs.js
SELECT * FROM "User" WHERE email='invite@example.test' AND role='RECRUITER' AND NOT suspended;

-- WRITE W10 | Add a recruiter to an active company owned by the caller
-- Source: server/routes/jobs.js
BEGIN;
INSERT INTO "CompanyMember" ("companyId","userId")
SELECT id,3 FROM "Company" WHERE id=1 AND "recruiterId"=1 AND NOT suspended;
ROLLBACK;

-- WRITE W11 | Remove a recruiter from an owned active company
-- Source: server/routes/jobs.js
BEGIN;
DELETE FROM "CompanyMember" m USING "Company" c
WHERE m."companyId"=c.id AND c.id=1 AND c."recruiterId"=1 AND NOT c.suspended AND m."userId"=2;
ROLLBACK;

-- READ R10 | Search and sort job openings as a candidate
-- Source: server/routes/jobs.js
WITH filter AS (
    SELECT '%analyst%'::text AS term,'all'::text AS scope,'%Pune%'::text AS location,
           'Remote'::text AS mode,'Internship'::text AS employment,'Entry level'::text AS experience,
           'newest'::text AS sort, 'no'::text AS applied
)
SELECT j.*,to_jsonb(c) AS company,
       ARRAY(SELECT a.id FROM "Application" a WHERE a."jobId"=j.id AND a."candidateId"=101) AS my_applications
FROM "Job" j JOIN "Company" c ON c.id = j."companyId" CROSS JOIN filter f
WHERE j."isOpen" AND j.publication = 'Published' AND NOT c.suspended
  AND (j.deadline IS NULL OR j.deadline > TIMESTAMP '2026-11-17 12:00')
  AND ((f.scope IN ('all','title') AND j.title ILIKE f.term)
    OR (f.scope IN ('all','skills') AND j."requiredSkills" ILIKE f.term)
    OR (f.scope IN ('all','location') AND j.location ILIKE f.term)
    OR (f.scope IN ('all','company') AND c.name ILIKE f.term)
    OR (f.scope IN ('all','description') AND j.description ILIKE f.term))
  AND (f.location IS NULL OR j.location ILIKE f.location)
  AND (f.mode IS NULL OR j."workMode"=f.mode)
  AND (f.employment IS NULL OR j."employmentType"=f.employment)
  AND (f.experience IS NULL OR j."experienceLevel"=f.experience)
  AND (f.applied IS NULL OR (f.applied='yes') = EXISTS (
      SELECT 1 FROM "Application" a WHERE a."jobId"=j.id AND a."candidateId"=101))
ORDER BY CASE WHEN f.sort='title' THEN j.title END,
         CASE WHEN f.sort='oldest' THEN j."createdAt" END,
         CASE WHEN f.sort='newest' THEN j."createdAt" END DESC,
         CASE WHEN f.sort='newest' THEN j.id END DESC,j.id
LIMIT 6 OFFSET 0;

-- READ R11 | Count job search results as a candidate
-- Source: server/routes/jobs.js
WITH filter AS (
    SELECT '%analyst%'::text AS term,'all'::text AS scope,'%Pune%'::text AS location,
           'Remote'::text AS mode,'Internship'::text AS employment,'Entry level'::text AS experience,
           'newest'::text AS sort, 'no'::text AS applied
)
SELECT COUNT(*)
FROM "Job" j JOIN "Company" c ON c.id = j."companyId" CROSS JOIN filter f
WHERE j."isOpen" AND j.publication = 'Published' AND NOT c.suspended
  AND (j.deadline IS NULL OR j.deadline > TIMESTAMP '2026-11-17 12:00')
  AND ((f.scope IN ('all','title') AND j.title ILIKE f.term)
    OR (f.scope IN ('all','skills') AND j."requiredSkills" ILIKE f.term)
    OR (f.scope IN ('all','location') AND j.location ILIKE f.term)
    OR (f.scope IN ('all','company') AND c.name ILIKE f.term)
    OR (f.scope IN ('all','description') AND j.description ILIKE f.term))
  AND (f.location IS NULL OR j.location ILIKE f.location)
  AND (f.mode IS NULL OR j."workMode"=f.mode)
  AND (f.employment IS NULL OR j."employmentType"=f.employment)
  AND (f.experience IS NULL OR j."experienceLevel"=f.experience)
  AND (f.applied IS NULL OR (f.applied='yes') = EXISTS (
      SELECT 1 FROM "Application" a WHERE a."jobId"=j.id AND a."candidateId"=101));

-- READ R12 | Search and sort job openings as a recruiter
-- Source: server/routes/jobs.js
WITH filter AS (
    SELECT '%analyst%'::text AS term,'all'::text AS scope,'%Pune%'::text AS location,
           'Remote'::text AS mode,'Internship'::text AS employment,'Entry level'::text AS experience,
           'newest'::text AS sort, 'Published'::text AS publication,true AS open
)
SELECT j.*,to_jsonb(c) AS company,
       (SELECT COUNT(*) FROM "Application" a WHERE a."jobId"=j.id) AS applicants
FROM "Job" j JOIN "Company" c ON c.id = j."companyId" CROSS JOIN filter f
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
))
  AND ((f.scope IN ('all','title') AND j.title ILIKE f.term)
    OR (f.scope IN ('all','skills') AND j."requiredSkills" ILIKE f.term)
    OR (f.scope IN ('all','location') AND j.location ILIKE f.term)
    OR (f.scope IN ('all','company') AND c.name ILIKE f.term)
    OR (f.scope IN ('all','description') AND j.description ILIKE f.term))
  AND (f.location IS NULL OR j.location ILIKE f.location)
  AND (f.mode IS NULL OR j."workMode"=f.mode)
  AND (f.employment IS NULL OR j."employmentType"=f.employment)
  AND (f.experience IS NULL OR j."experienceLevel"=f.experience)
  AND (f.publication IS NULL OR j.publication=f.publication)
  AND (f.open IS NULL OR j."isOpen"=f.open)
ORDER BY CASE WHEN f.sort='title' THEN j.title END,
         CASE WHEN f.sort='oldest' THEN j."createdAt" END,
         CASE WHEN f.sort='newest' THEN j."createdAt" END DESC,
         CASE WHEN f.sort='newest' THEN j.id END DESC,j.id
LIMIT 6 OFFSET 0;

-- READ R13 | Count job search results as a recruiter
-- Source: server/routes/jobs.js
WITH filter AS (
    SELECT '%analyst%'::text AS term,'all'::text AS scope,'%Pune%'::text AS location,
           'Remote'::text AS mode,'Internship'::text AS employment,'Entry level'::text AS experience,
           'newest'::text AS sort, 'Published'::text AS publication,true AS open
)
SELECT COUNT(*)
FROM "Job" j JOIN "Company" c ON c.id = j."companyId" CROSS JOIN filter f
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
))
  AND ((f.scope IN ('all','title') AND j.title ILIKE f.term)
    OR (f.scope IN ('all','skills') AND j."requiredSkills" ILIKE f.term)
    OR (f.scope IN ('all','location') AND j.location ILIKE f.term)
    OR (f.scope IN ('all','company') AND c.name ILIKE f.term)
    OR (f.scope IN ('all','description') AND j.description ILIKE f.term))
  AND (f.location IS NULL OR j.location ILIKE f.location)
  AND (f.mode IS NULL OR j."workMode"=f.mode)
  AND (f.employment IS NULL OR j."employmentType"=f.employment)
  AND (f.experience IS NULL OR j."experienceLevel"=f.experience)
  AND (f.publication IS NULL OR j.publication=f.publication)
  AND (f.open IS NULL OR j."isOpen"=f.open);

-- READ R14 | Verify team access before posting a job
-- Source: server/routes/jobs.js
SELECT c.* FROM "Company" c WHERE c.id=1 AND NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
));

-- WRITE W12 | Post a job with its terms and publication status
-- Source: server/routes/jobs.js
BEGIN;
INSERT INTO "Job" ("companyId",title,location,description,"workMode","employmentType",
                   "experienceLevel","requiredSkills",compensation,deadline,publication,"isOpen")
VALUES (1,'Graduate Analyst','Pune','Analyze data','Remote','Internship','Entry level',
        'SQL','Stipend',TIMESTAMP '2026-12-15','Published',true) RETURNING *;
ROLLBACK;

-- READ R15 | Read a managed job before validating its publication change
-- Source: server/routes/jobs.js
SELECT j.* FROM "Job" j JOIN "Company" c ON c.id = j."companyId"
WHERE j.id=1 AND NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
));

-- WRITE W13 | Edit a managed job if its publication status is unchanged
-- Source: server/routes/jobs.js
BEGIN;
UPDATE "Job" SET title='Graduate Analyst',location='Pune',description='Analyze data',
    "workMode"='Hybrid',"employmentType"='Internship',"experienceLevel"='Entry level',
    "requiredSkills"='SQL',compensation='Stipend',deadline=NULL,publication='Closed',"isOpen"=false
WHERE id=1 AND publication='Published' AND id IN (SELECT j.id FROM "Job" j JOIN "Company" c ON c.id = j."companyId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
))) RETURNING *;
ROLLBACK;

-- READ R16 | Read a candidate profile
-- Source: server/routes/jobs.js
SELECT * FROM "Profile" WHERE "userId"=101;

-- WRITE W14 | Save profile fields and the shared resume link
-- Source: server/routes/jobs.js
BEGIN;
UPDATE "Profile" SET headline='Data analyst',skills='SQL',summary='Graduate',
    experience='Internship',education='B.Tech',projects='Capstone',
    "resumeName"='resume.pdf',"resumeUrl"='https://example.test/resume.pdf'
WHERE "userId"=101 RETURNING *;
ROLLBACK;

-- READ R17 | Page through jobs for per-job analytics
-- Source: server/routes/jobs.js
SELECT j.id,j.title,c.name FROM "Job" j JOIN "Company" c ON c.id = j."companyId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
)) AND c.id=1 ORDER BY j.id DESC LIMIT 6 OFFSET 0;

-- READ R18 | Group the current job page’s applications by job and stage
-- Source: server/routes/jobs.js
SELECT "jobId",stage,COUNT(*) FROM "Application"
WHERE "jobId" IN (10,9,8,7,6,5) GROUP BY "jobId",stage;

-- READ R19 | Count managed jobs for analytics totals and pagination
-- Source: server/routes/jobs.js
SELECT COUNT(*) FROM "Job" j JOIN "Company" c ON c.id = j."companyId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
)) AND c.id=1;

-- READ R20 | Count company applications in each stage
-- Source: server/routes/jobs.js
SELECT a.stage,COUNT(*) FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
)) AND c.id=1 GROUP BY a.stage;

-- READ R21 | Fetch 30 days of timestamps for the total and 14-day chart
-- Source: server/routes/jobs.js
SELECT a."createdAt" FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
)) AND c.id=1 AND a."createdAt">=TIMESTAMP '2026-11-17 12:00' - INTERVAL '30 days';

-- READ R22 | Rank five managed jobs with the most applications
-- Source: server/routes/jobs.js
SELECT j.id,j.title,COUNT(*) AS applications FROM "Job" j JOIN "Company" c ON c.id = j."companyId"
JOIN "Application" a ON a."jobId"=j.id
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
)) AND c.id=1 GROUP BY j.id ORDER BY applications DESC,j.id LIMIT 5;

-- READ R23 | Count unfinished interviews in the company pipeline
-- Source: server/routes/jobs.js
SELECT COUNT(*) FROM "Interview" i
JOIN "Application" a ON a.id = i."applicationId"
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
)) AND c.id=1 AND NOT i.completed AND a.stage='INTERVIEW';

-- READ R24 | Count company jobs currently accepting applications
-- Source: server/routes/jobs.js
SELECT COUNT(*) FROM "Job" j JOIN "Company" c ON c.id = j."companyId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
)) AND c.id=1 AND j."isOpen" AND j.publication = 'Published' AND NOT c.suspended
  AND (j.deadline IS NULL OR j.deadline > TIMESTAMP '2026-11-17 12:00');

-- READ R25 | List the candidate’s saved resume metadata
-- Source: server/routes/resumes.js
SELECT id,name,"isDefault" FROM "SavedResume" WHERE "userId"=101 ORDER BY id DESC;

-- READ R26 | Download a candidate-owned saved PDF
-- Source: server/routes/resumes.js
SELECT * FROM "SavedResume" WHERE id=1 AND "userId"=101;

-- WRITE W15 | Upload a saved resume and return its metadata
-- Source: server/routes/resumes.js
BEGIN;
INSERT INTO "SavedResume" ("userId",name,content)
VALUES (101,'new.pdf',convert_to('%PDF-1.4 fixture','UTF8')) RETURNING id,name,"isDefault";
ROLLBACK;

-- WRITE W16 | Clear a candidate’s existing default resume
-- Source: server/routes/resumes.js
BEGIN;
UPDATE "SavedResume" SET "isDefault"=false WHERE "userId"=101 AND "isDefault";
ROLLBACK;

-- WRITE W17 | Set the selected owned resume as default
-- Source: server/routes/resumes.js
BEGIN;
UPDATE "SavedResume" SET "isDefault"=true WHERE id=4 AND "userId"=102 RETURNING id,name,"isDefault";
ROLLBACK;

-- WRITE W18 | Delete an owned saved resume
-- Source: server/routes/resumes.js
BEGIN;
DELETE FROM "SavedResume" WHERE id=2 AND "userId"=101 RETURNING id,name,"isDefault";
ROLLBACK;

-- READ R27 | Open an application and its history as a candidate
-- Source: server/routes/applications.js
SELECT a.*,to_jsonb(j) AS job,c.name AS company_name,u.name AS candidate_name,
       u.email,to_jsonb(p) AS profile,pdf.name AS resume_name,CASE WHEN i.id IS NOT NULL THEN jsonb_build_object(
           'scheduledAt',i."scheduledAt",'location',i.location,
           'confirmed',i.confirmed,'completed',i.completed) END AS interview,ARRAY(SELECT to_jsonb(e) FROM "ApplicationEvent" e
             WHERE e."applicationId"=a.id ORDER BY e.id DESC) AS history
FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
JOIN "User" u ON u.id = a."candidateId"
LEFT JOIN "Profile" p ON p."userId"=u.id
LEFT JOIN "ApplicationResume" pdf ON pdf."applicationId"=a.id
LEFT JOIN "Interview" i ON i."applicationId"=a.id
WHERE a.id=1 AND a."candidateId"=101;

-- READ R28 | Search paginated applications as a candidate
-- Source: server/routes/applications.js
SELECT a.*,to_jsonb(j) AS job,c.name AS company_name,u.name AS candidate_name,
       u.email,to_jsonb(p) AS profile,pdf.name AS resume_name,CASE WHEN i.id IS NOT NULL THEN jsonb_build_object(
           'scheduledAt',i."scheduledAt",'location',i.location,
           'confirmed',i.confirmed,'completed',i.completed) END AS interview
FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
JOIN "User" u ON u.id = a."candidateId"
LEFT JOIN "Profile" p ON p."userId"=u.id
LEFT JOIN "ApplicationResume" pdf ON pdf."applicationId"=a.id
LEFT JOIN "Interview" i ON i."applicationId"=a.id
WHERE a."candidateId"=101
  AND (u.name ILIKE '%analyst%' OR j.title ILIKE '%analyst%' OR c.name ILIKE '%analyst%')
  AND a."jobId"=1 AND a.stage='INTERVIEW' 
ORDER BY a.id DESC LIMIT 6 OFFSET 0;

-- READ R29 | Count filtered applications as a candidate
-- Source: server/routes/applications.js
SELECT COUNT(*) FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
JOIN "User" u ON u.id = a."candidateId"
WHERE a."candidateId"=101
  AND (u.name ILIKE '%analyst%' OR j.title ILIKE '%analyst%' OR c.name ILIKE '%analyst%')
  AND a."jobId"=1 AND a.stage='INTERVIEW';

-- READ R30 | Retrieve the submitted PDF as a candidate
-- Source: server/routes/applications.js
SELECT pdf.* FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
JOIN "ApplicationResume" pdf ON pdf."applicationId"=a.id
WHERE a.id=1 AND a."candidateId"=101;

-- READ R31 | Group overview applications by stage as a candidate
-- Source: server/routes/applications.js
SELECT a.stage,COUNT(*) FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
WHERE a."candidateId"=101 GROUP BY a.stage;

-- READ R32 | Read four recent applications for the candidate overview
-- Source: server/routes/applications.js
SELECT a.*,u.name AS candidate,p."resumeUrl",pdf.name AS submitted_resume,
       to_jsonb(j) AS job,c.name AS company FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
JOIN "User" u ON u.id = a."candidateId"
LEFT JOIN "Profile" p ON p."userId"=u.id
LEFT JOIN "ApplicationResume" pdf ON pdf."applicationId"=a.id
WHERE a."candidateId"=101 ORDER BY a.id DESC LIMIT 4;

-- READ R33 | Read three upcoming interviews for the candidate overview
-- Source: server/routes/applications.js
SELECT i.id,i."scheduledAt",i.location,to_jsonb(j) AS job,c.name AS company,u.name AS candidate
FROM "Interview" i
JOIN "Application" a ON a.id = i."applicationId"
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
JOIN "User" u ON u.id = a."candidateId"
WHERE a."candidateId"=101
  AND a.stage='INTERVIEW' AND NOT i.completed AND i."scheduledAt">=TIMESTAMP '2026-11-17 12:00'
ORDER BY i."scheduledAt" LIMIT 3;

-- READ R34 | Count open jobs for the candidate overview
-- Source: server/routes/applications.js
SELECT COUNT(*) FROM "Job" j JOIN "Company" c ON c.id = j."companyId"
WHERE j."isOpen" AND j.publication = 'Published' AND NOT c.suspended
  AND (j.deadline IS NULL OR j.deadline > TIMESTAMP '2026-11-17 12:00');

-- READ R35 | List interview appointments visible to the candidate
-- Source: server/routes/applications.js
SELECT i."scheduledAt",i.location,i.confirmed,i.completed,a.id AS application_id,
       a.stage,j.title,u.name AS candidate FROM "Interview" i
JOIN "Application" a ON a.id = i."applicationId"
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
JOIN "User" u ON u.id = a."candidateId"
WHERE a."candidateId"=101 ORDER BY i."scheduledAt" DESC LIMIT 6 OFFSET 0;

-- READ R36 | Count interviews visible to the candidate
-- Source: server/routes/applications.js
SELECT COUNT(*) FROM "Interview" i
JOIN "Application" a ON a.id = i."applicationId"
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
WHERE a."candidateId"=101;

-- READ R37 | Open an application and its history as a recruiter
-- Source: server/routes/applications.js
SELECT a.*,to_jsonb(j) AS job,c.name AS company_name,u.name AS candidate_name,
       u.email,to_jsonb(p) AS profile,pdf.name AS resume_name,to_jsonb(i) AS interview,ARRAY(SELECT to_jsonb(e) FROM "ApplicationEvent" e
             WHERE e."applicationId"=a.id ORDER BY e.id DESC) AS history,ARRAY(SELECT to_jsonb(n) FROM "RecruiterNote" n
             WHERE n."applicationId"=a.id ORDER BY n.id DESC) AS private_notes
FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
JOIN "User" u ON u.id = a."candidateId"
LEFT JOIN "Profile" p ON p."userId"=u.id
LEFT JOIN "ApplicationResume" pdf ON pdf."applicationId"=a.id
LEFT JOIN "Interview" i ON i."applicationId"=a.id
WHERE a.id=1 AND NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
));

-- READ R38 | Search paginated applications as a recruiter
-- Source: server/routes/applications.js
SELECT a.*,to_jsonb(j) AS job,c.name AS company_name,u.name AS candidate_name,
       u.email,to_jsonb(p) AS profile,pdf.name AS resume_name,to_jsonb(i) AS interview
FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
JOIN "User" u ON u.id = a."candidateId"
LEFT JOIN "Profile" p ON p."userId"=u.id
LEFT JOIN "ApplicationResume" pdf ON pdf."applicationId"=a.id
LEFT JOIN "Interview" i ON i."applicationId"=a.id
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
))
  AND (u.name ILIKE '%analyst%' OR j.title ILIKE '%analyst%' OR c.name ILIKE '%analyst%')
  AND a."jobId"=1 AND a.stage='INTERVIEW' 
ORDER BY a.id DESC LIMIT 6 OFFSET 0;

-- READ R39 | Count filtered applications as a recruiter
-- Source: server/routes/applications.js
SELECT COUNT(*) FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
JOIN "User" u ON u.id = a."candidateId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
))
  AND (u.name ILIKE '%analyst%' OR j.title ILIKE '%analyst%' OR c.name ILIKE '%analyst%')
  AND a."jobId"=1 AND a.stage='INTERVIEW';

-- READ R40 | Retrieve the submitted PDF as a recruiter
-- Source: server/routes/applications.js
SELECT pdf.* FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
JOIN "ApplicationResume" pdf ON pdf."applicationId"=a.id
WHERE a.id=1 AND NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
));

-- READ R41 | Group overview applications by stage as a recruiter
-- Source: server/routes/applications.js
SELECT a.stage,COUNT(*) FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
)) GROUP BY a.stage;

-- READ R42 | Read four recent applications for the recruiter overview
-- Source: server/routes/applications.js
SELECT a.*,u.name AS candidate,p."resumeUrl",pdf.name AS submitted_resume,
       to_jsonb(j) AS job,c.name AS company FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
JOIN "User" u ON u.id = a."candidateId"
LEFT JOIN "Profile" p ON p."userId"=u.id
LEFT JOIN "ApplicationResume" pdf ON pdf."applicationId"=a.id
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
)) ORDER BY a.id DESC LIMIT 4;

-- READ R43 | Read three upcoming interviews for the recruiter overview
-- Source: server/routes/applications.js
SELECT i.id,i."scheduledAt",i.location,to_jsonb(j) AS job,c.name AS company,u.name AS candidate
FROM "Interview" i
JOIN "Application" a ON a.id = i."applicationId"
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
JOIN "User" u ON u.id = a."candidateId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
))
  AND a.stage='INTERVIEW' AND NOT i.completed AND i."scheduledAt">=TIMESTAMP '2026-11-17 12:00'
ORDER BY i."scheduledAt" LIMIT 3;

-- READ R44 | Count open jobs for the recruiter overview
-- Source: server/routes/applications.js
SELECT COUNT(*) FROM "Job" j JOIN "Company" c ON c.id = j."companyId"
WHERE j."isOpen" AND j.publication = 'Published' AND NOT c.suspended
  AND (j.deadline IS NULL OR j.deadline > TIMESTAMP '2026-11-17 12:00') AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
));

-- READ R45 | List interview appointments visible to the recruiter
-- Source: server/routes/applications.js
SELECT i."scheduledAt",i.location,i.confirmed,i.completed,a.id AS application_id,
       a.stage,j.title,u.name AS candidate FROM "Interview" i
JOIN "Application" a ON a.id = i."applicationId"
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
JOIN "User" u ON u.id = a."candidateId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
)) ORDER BY i."scheduledAt" DESC LIMIT 6 OFFSET 0;

-- READ R46 | Count interviews visible to the recruiter
-- Source: server/routes/applications.js
SELECT COUNT(*) FROM "Interview" i
JOIN "Application" a ON a.id = i."applicationId"
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
));

-- READ R47 | Check that a job accepts applications before submitting
-- Source: server/routes/applications.js
SELECT j.* FROM "Job" j JOIN "Company" c ON c.id = j."companyId"
WHERE j.id=5 AND j."isOpen" AND j.publication = 'Published' AND NOT c.suspended
  AND (j.deadline IS NULL OR j.deadline > TIMESTAMP '2026-11-17 12:00');

-- READ R48 | Read the selected saved resume to copy into an application
-- Source: server/routes/applications.js
SELECT name,content FROM "SavedResume" WHERE id=1 AND "userId"=101;

-- WRITE W19 | Create a job application (also used by demo seeding)
-- Source: server/routes/applications.js
BEGIN;
INSERT INTO "Application" ("jobId","candidateId","coverNote")
VALUES (5,101,'Interested in the role') RETURNING *;
ROLLBACK;

-- WRITE W20 | Attach a snapshot of the uploaded or saved PDF
-- Source: server/routes/applications.js
BEGIN;
INSERT INTO "ApplicationResume" ("applicationId",name,content)
VALUES (2,'submitted.pdf',convert_to('%PDF-1.4 fixture','UTF8')) RETURNING "applicationId";
ROLLBACK;

-- WRITE W21 | Record a submission, stage or interview event
-- Source: server/routes/applications.js
BEGIN;
INSERT INTO "ApplicationEvent" ("applicationId",message,actor,seen)
VALUES (2,'Stage changed to shortlisted','Recruiter One',false) RETURNING *;
ROLLBACK;

-- READ R49 | Load a team application before stage validation or scheduling
-- Source: server/routes/applications.js
SELECT a.* FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
WHERE a.id=2 AND NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
));

-- WRITE W22 | Change the application stage if the reviewed stage still matches
-- Source: server/routes/applications.js
BEGIN;
UPDATE "Application" SET stage='SHORTLISTED'
WHERE id=2 AND stage='IN_REVIEW' AND id IN (SELECT a.id FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
))) RETURNING *;
ROLLBACK;

-- READ R50 | Detect a candidate or recruiter interview slot conflict
-- Source: server/routes/applications.js
SELECT i.* FROM "Interview" i
JOIN "Application" a ON a.id = i."applicationId"
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
WHERE i."applicationId"<>2 AND NOT i.completed AND a.stage='INTERVIEW'
  AND i."scheduledAt">TIMESTAMP '2026-11-18 14:00' - INTERVAL '30 minutes'
  AND i."scheduledAt"<TIMESTAMP '2026-11-18 14:00' + INTERVAL '30 minutes'
  AND (a."candidateId"=102 OR i."interviewerId"=1 OR (i."interviewerId" IS NULL AND c."recruiterId"=1))
LIMIT 1;

-- WRITE W23 | Move an eligible team application into the interview stage
-- Source: server/routes/applications.js
BEGIN;
UPDATE "Application" a SET stage='INTERVIEW'
WHERE a.id=2 AND a.id IN (SELECT a.id FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
))) AND stage IN ('IN_REVIEW','SHORTLISTED','INTERVIEW')
  AND NOT EXISTS (SELECT 1 FROM "Interview" i WHERE i."applicationId"=a.id AND i.completed);
ROLLBACK;

-- WRITE W24 | Schedule an interview and clear prior confirmation on conflict
-- Source: server/routes/applications.js
BEGIN;
INSERT INTO "Interview" ("applicationId","scheduledAt",location,"interviewerId")
VALUES (2,TIMESTAMP '2026-11-24 14:00','Room B',1)
ON CONFLICT ("applicationId") DO UPDATE
SET "scheduledAt"=EXCLUDED."scheduledAt",location=EXCLUDED.location,
    "interviewerId"=EXCLUDED."interviewerId",confirmed=false,completed=false
RETURNING *;
ROLLBACK;

-- WRITE W25 | Reschedule an interview and clear prior confirmation on conflict
-- Source: server/routes/applications.js
BEGIN;
INSERT INTO "Interview" ("applicationId","scheduledAt",location,"interviewerId")
VALUES (1,TIMESTAMP '2026-11-24 14:00','Room B',1)
ON CONFLICT ("applicationId") DO UPDATE
SET "scheduledAt"=EXCLUDED."scheduledAt",location=EXCLUDED.location,
    "interviewerId"=EXCLUDED."interviewerId",confirmed=false,completed=false
RETURNING *;
ROLLBACK;

-- WRITE W26 | Confirm attendance for the candidate’s unchanged invitation
-- Source: server/routes/applications.js
BEGIN;
UPDATE "Interview" i SET confirmed=true FROM "Application" a
WHERE i."applicationId"=a.id AND a.id=1 AND a."candidateId"=101 AND a.stage='INTERVIEW'
  AND NOT i.completed AND i."scheduledAt"=TIMESTAMP '2026-11-18 14:00' AND i.location='Room A';
ROLLBACK;

-- WRITE W27 | Save private interview feedback as a team recruiter
-- Source: server/routes/applications.js
BEGIN;
UPDATE "Interview" SET feedback='Clear examples'
WHERE "applicationId"=1 AND "applicationId" IN (SELECT a.id FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
))) RETURNING *;
ROLLBACK;

-- WRITE W28 | Add a private note to an accessible application
-- Source: server/routes/applications.js
BEGIN;
INSERT INTO "RecruiterNote" ("applicationId",text)
SELECT a.id,'Review project details' FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
WHERE a.id=1 AND NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
));
ROLLBACK;

-- WRITE W29 | Withdraw a candidate’s active application
-- Source: server/routes/applications.js
BEGIN;
UPDATE "Application" SET stage='WITHDRAWN'
WHERE id=1 AND "candidateId"=101 AND stage IN ('APPLIED','IN_REVIEW','SHORTLISTED','INTERVIEW','OFFERED')
RETURNING id;
ROLLBACK;

-- WRITE W30 | Return a team application with an unfinished interview to the shortlist
-- Source: server/routes/applications.js
BEGIN;
UPDATE "Application" a SET stage='SHORTLISTED'
WHERE a.id=1 AND a.stage='INTERVIEW' AND a.id IN (SELECT a.id FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
)))
  AND EXISTS (SELECT 1 FROM "Interview" i WHERE i."applicationId"=a.id AND NOT i.completed)
RETURNING id;
ROLLBACK;

-- WRITE W31 | Remove the interview slot during cancellation
-- Source: server/routes/applications.js
BEGIN;
DELETE FROM "Interview" WHERE "applicationId"=1 RETURNING id;
ROLLBACK;

-- WRITE W32 | Mark a past unfinished interview complete for an authorized recruiter
-- Source: server/routes/applications.js
BEGIN;
UPDATE "Interview" i SET completed=true
WHERE i."applicationId"=4 AND NOT i.completed AND i."scheduledAt"<=TIMESTAMP '2026-11-17 12:00'
  AND i."applicationId" IN (SELECT a.id FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
WHERE NOT c.suspended AND (c."recruiterId" = 1 OR EXISTS (
    SELECT 1 FROM "CompanyMember" m WHERE m."companyId" = c.id AND m."userId" = 1
)) AND a.stage='INTERVIEW') RETURNING id;
ROLLBACK;

-- READ R51 | List a candidate’s application notifications
-- Source: server/routes/applications.js
SELECT e.*,a.id AS application_id,j.title FROM "ApplicationEvent" e JOIN "Application" a ON a.id=e."applicationId"
JOIN "Job" j ON j.id=a."jobId"
WHERE a."candidateId"=101 ORDER BY e.id DESC LIMIT 6 OFFSET 0;

-- READ R52 | Count the candidate’s notifications
-- Source: server/routes/applications.js
SELECT COUNT(*) FROM "ApplicationEvent" e JOIN "Application" a ON a.id=e."applicationId"
WHERE a."candidateId"=101;

-- WRITE W33 | Mark a notification read for its candidate
-- Source: server/routes/applications.js
BEGIN;
UPDATE "ApplicationEvent" e SET seen=true FROM "Application" a
WHERE e.id=1 AND a.id=e."applicationId" AND a."candidateId"=101 RETURNING e.id;
ROLLBACK;

-- READ R53 | Search accounts for the administrator
-- Source: server/routes/admin.js
SELECT id,name,email,role,suspended FROM "User" WHERE name ILIKE '%candidate%' OR email ILIKE '%candidate%' ORDER BY id DESC LIMIT 6 OFFSET 0;

-- READ R54 | Count matching administrator search results
-- Source: server/routes/admin.js
SELECT COUNT(*) FROM "User" WHERE name ILIKE '%candidate%' OR email ILIKE '%candidate%';

-- READ R55 | Read the ten most recent admin actions
-- Source: server/routes/admin.js
SELECT * FROM "AdminAction" ORDER BY id DESC LIMIT 10;

-- READ R56 | Count all companies for administration
-- Source: server/routes/admin.js
SELECT COUNT(*) FROM "Company";

-- READ R57 | Count all jobs for administration
-- Source: server/routes/admin.js
SELECT COUNT(*) FROM "Job";

-- READ R58 | Count all applications for administration
-- Source: server/routes/admin.js
SELECT COUNT(*) FROM "Application";

-- WRITE W34 | Suspend or reactivate a non-admin in the expected current state
-- Source: server/routes/admin.js
BEGIN;
UPDATE "User" SET suspended=true WHERE id=101 AND role<>'ADMIN' AND suspended=false RETURNING *;
ROLLBACK;

-- WRITE W35 | Record a user or company administration action
-- Source: server/routes/admin.js
BEGIN;
INSERT INTO "AdminAction" (actor,message) VALUES ('admin@example.test','Suspended c1@example.test') RETURNING *;
ROLLBACK;

-- READ R59 | List companies and owner emails for administration
-- Source: server/routes/admin.js
SELECT c.*,u.email AS owner_email FROM "Company" c JOIN "User" u ON u.id=c."recruiterId"
WHERE c.name ILIKE '%company%' ORDER BY c.id DESC LIMIT 6 OFFSET 0;

-- READ R60 | Count companies matching the admin search
-- Source: server/routes/admin.js
SELECT COUNT(*) FROM "Company" WHERE name ILIKE '%company%';

-- WRITE W36 | Suspend or reactivate a company in the expected state
-- Source: server/routes/admin.js
BEGIN;
UPDATE "Company" SET suspended=true WHERE id=1 AND suspended=false RETURNING *;
ROLLBACK;

-- READ R61 | Find the seeded application for the sample resume
-- Source: prisma/seed.js and prisma/create-admin.js
SELECT a.* FROM "Application" a
JOIN "Job" j ON j.id = a."jobId"
JOIN "Company" c ON c.id = j."companyId"
JOIN "User" u ON u.id = a."candidateId"
JOIN "User" owner ON owner.id=c."recruiterId"
WHERE u.email='c1@example.test' AND j.title='Analyst 1'
  AND c.name='Company 1' AND owner.email='owner@example.test'
ORDER BY a.id LIMIT 1;

-- WRITE W37 | Insert the sample PDF if the seeded application lacks one
-- Source: prisma/seed.js and prisma/create-admin.js
BEGIN;
INSERT INTO "ApplicationResume" ("applicationId",name,content)
VALUES (2,'demo.pdf',convert_to('%PDF-1.4 fixture','UTF8'))
ON CONFLICT ("applicationId") DO NOTHING;
ROLLBACK;

-- WRITE W38 | Create a demo candidate with its initial headline and skills
-- Source: prisma/seed.js and prisma/create-admin.js
BEGIN;
WITH account AS (
    INSERT INTO "User" (name,email,role,"passwordHash")
    VALUES ('Demo Student','demo-student@example.test','CANDIDATE','fixture-hash') RETURNING id
)
INSERT INTO "Profile" ("userId",headline,skills) SELECT id,'Final-year student','SQL' FROM account;
ROLLBACK;

-- WRITE W39 | Seed an application at a specified initial stage
-- Source: prisma/seed.js and prisma/create-admin.js
BEGIN;
INSERT INTO "Application" ("candidateId","jobId",stage)
VALUES (101,5,'INTERVIEW') RETURNING *;
ROLLBACK;

-- WRITE W40 | Insert a seeded meeting without an assigned interviewer
-- Source: prisma/seed.js and prisma/create-admin.js
BEGIN;
INSERT INTO "Interview" ("applicationId","scheduledAt",location)
VALUES (2,TIMESTAMP '2026-11-24 14:00','Room A') RETURNING *;
ROLLBACK;
