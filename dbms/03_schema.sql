
BEGIN;

CREATE TYPE "Role" AS ENUM ('RECRUITER', 'CANDIDATE', 'ADMIN');
CREATE TYPE "Stage" AS ENUM (
    'APPLIED', 'SHORTLISTED', 'INTERVIEW', 'HIRED', 'REJECTED',
    'IN_REVIEW', 'OFFERED', 'WITHDRAWN'
);

-- Accounts and candidate records
CREATE TABLE "User" (
    "id"           SERIAL PRIMARY KEY,
    "name"         TEXT NOT NULL,
    "email"        TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "role"         "Role" NOT NULL,
    "suspended"    BOOLEAN NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX "User_email_key" ON "User" ("email");

CREATE TABLE "Session" (
    "token"     TEXT PRIMARY KEY,
    "userId"    INTEGER NOT NULL REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    "expiresAt" TIMESTAMP(3) NOT NULL
);

CREATE TABLE "Profile" (
    "userId"     INTEGER PRIMARY KEY REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    "headline"   TEXT NOT NULL DEFAULT '',
    "skills"     TEXT NOT NULL DEFAULT '',
    "resumeName" TEXT NOT NULL DEFAULT '',
    "resumeUrl"  TEXT NOT NULL DEFAULT '',
    "education"  TEXT NOT NULL DEFAULT '',
    "experience" TEXT NOT NULL DEFAULT '',
    "projects"   TEXT NOT NULL DEFAULT '',
    "summary"    TEXT NOT NULL DEFAULT ''
);

CREATE TABLE "SavedResume" (
    "id"        SERIAL PRIMARY KEY,
    "userId"    INTEGER NOT NULL REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    "name"      TEXT NOT NULL,
    "content"   BYTEA NOT NULL,
    "isDefault" BOOLEAN NOT NULL DEFAULT false
);
-- A candidate can save several PDFs and select at most one as the default.
CREATE UNIQUE INDEX "one_default_resume" ON "SavedResume" ("userId") WHERE "isDefault";

-- Companies and job openings
CREATE TABLE "Company" (
    "id"          SERIAL PRIMARY KEY,
    "name"        TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "recruiterId" INTEGER NOT NULL REFERENCES "User" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    "suspended"   BOOLEAN NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX "Company_recruiterId_name_key" ON "Company" ("recruiterId", "name");

CREATE TABLE "CompanyMember" (
    "companyId" INTEGER NOT NULL REFERENCES "Company" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    "userId"    INTEGER NOT NULL REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    PRIMARY KEY ("companyId", "userId")
);

CREATE TABLE "Job" (
    "id"              SERIAL PRIMARY KEY,
    "title"           TEXT NOT NULL,
    "location"        TEXT NOT NULL,
    "description"     TEXT NOT NULL,
    "isOpen"          BOOLEAN NOT NULL DEFAULT true,
    "createdAt"       TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "companyId"       INTEGER NOT NULL REFERENCES "Company" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    "workMode"        TEXT NOT NULL DEFAULT '',
    "requiredSkills"  TEXT NOT NULL DEFAULT '',
    "employmentType"  TEXT NOT NULL DEFAULT '',
    "experienceLevel" TEXT NOT NULL DEFAULT '',
    "compensation"    TEXT NOT NULL DEFAULT '',
    "deadline"        TIMESTAMP(3),
    "publication"     TEXT NOT NULL DEFAULT 'Published'
);

-- Applications and interviews
CREATE TABLE "Application" (
    "id"          SERIAL PRIMARY KEY,
    "jobId"       INTEGER NOT NULL REFERENCES "Job" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    "candidateId" INTEGER NOT NULL REFERENCES "User" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    "stage"       "Stage" NOT NULL DEFAULT 'APPLIED',
    "createdAt"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "coverNote"   TEXT NOT NULL DEFAULT ''
);
CREATE UNIQUE INDEX "Application_jobId_candidateId_key" ON "Application" ("jobId", "candidateId");

-- Each application keeps its own copy of the submitted PDF.
CREATE TABLE "ApplicationResume" (
    "applicationId" INTEGER PRIMARY KEY REFERENCES "Application" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    "name"          TEXT NOT NULL,
    "content"       BYTEA NOT NULL
);

CREATE TABLE "Interview" (
    "id"            SERIAL PRIMARY KEY,
    "applicationId" INTEGER NOT NULL REFERENCES "Application" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    "scheduledAt"   TIMESTAMP(3) NOT NULL,
    "location"      TEXT NOT NULL,
    "feedback"      TEXT NOT NULL DEFAULT '',
    "confirmed"     BOOLEAN NOT NULL DEFAULT false,
    "completed"     BOOLEAN NOT NULL DEFAULT false,
    "interviewerId" INTEGER REFERENCES "User" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "Interview_applicationId_key" ON "Interview" ("applicationId");

CREATE TABLE "ApplicationEvent" (
    "id"            SERIAL PRIMARY KEY,
    "applicationId" INTEGER NOT NULL REFERENCES "Application" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    "message"       TEXT NOT NULL,
    "actor"         TEXT NOT NULL,
    "createdAt"     TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "seen"          BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE "RecruiterNote" (
    "id"            SERIAL PRIMARY KEY,
    "applicationId" INTEGER NOT NULL REFERENCES "Application" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    "text"          TEXT NOT NULL,
    "createdAt"     TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE "AdminAction" (
    "id"        SERIAL PRIMARY KEY,
    "actor"     TEXT NOT NULL,
    "message"   TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMIT;
