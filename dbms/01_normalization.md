# Database Normalization – LinkedIn Professional Networking & Jobs Database

## 1. Introduction

Normalization is the process of organizing database tables to reduce data redundancy and improve data integrity.

In this project, the database contains information about members, companies, jobs, skills, connections, invitations, applications, and profile views.

The database is designed with the objective of satisfying Third Normal Form (3NF), and where possible, Boyce-Codd Normal Form (BCNF).

The main objectives are:

- Reduce duplicate data.
- Avoid insertion, update, and deletion anomalies.
- Maintain consistency between related records.
- Store independent entities in separate tables.
- Establish relationships using primary keys and foreign keys.

## 2. Functional Dependencies

A functional dependency describes a relationship between attributes in a table.

If attribute X determines attribute Y, it is represented as:

`X → Y`

For example:

`member_id → first_name, last_name, email`

This means that a particular member ID determines the other details of that member.

## 3. Functional Dependencies and Normal Forms of Each Table

### 3.1 Cities

**Primary Key:** `city_id`

**Functional Dependency:**

`city_id → city_name, state`

**Normal Form:** 3NF / BCNF

Each city is identified by its city ID. City information is stored separately rather than repeated in members, companies, and jobs.

### 3.2 Members

**Primary Key:** `member_id`

**Functional Dependency:**

`member_id → first_name, last_name, headline, email, city_id, industry, is_premium, open_to_work, created_at`

**Normal Form:** 3NF / BCNF

Each member's profile information is stored in one record. City details are not repeated; `city_id` references the Cities table.

Email should also be treated as a candidate key if the schema enforces its uniqueness, including the case-insensitive uniqueness needed by the sign-in query.

### 3.3 Companies

**Primary Key:** `company_id`

**Functional Dependency:**

`company_id → company_name, industry, company_size, hq_city_id, founded_year, website`

**Normal Form:** 3NF / BCNF

Company information is stored separately. The headquarters city is referenced using `hq_city_id`, avoiding repeated city details.

### 3.4 Positions

**Primary Key:** `position_id`

**Functional Dependency:**

`position_id → member_id, company_id, title, employment_type, start_date, end_date`

**Normal Form:** 3NF / BCNF

Each position represents a member's work experience at a company. Member and company information is referenced using foreign keys instead of being duplicated.

### 3.5 Skills

**Primary Key:** `skill_id`

**Functional Dependency:**

`skill_id → skill_name`

**Normal Form:** 3NF / BCNF

Each skill is stored once and identified by its skill ID. Other tables reference it through foreign keys.

### 3.6 Member Skills

**Composite Primary Key:** `(member_id, skill_id)`

**Functional Dependency:**

`(member_id, skill_id) → endorsements`

**Normal Form:** 3NF / BCNF

A member can have multiple skills, and a skill can belong to multiple members. The composite key uniquely identifies each member-skill combination.

The endorsement count depends on the complete combination of member and skill.

### 3.7 Connections

**Composite Primary Key:** `(member_a, member_b)`

**Functional Dependency:**

`(member_a, member_b) → connected_at`

**Normal Form:** 3NF / BCNF

Connections represent a two-way relationship between members. Each pair is stored only once, with the smaller member ID stored in `member_a` and the larger ID in `member_b`.

The composite key uniquely identifies a connection.

### 3.8 Invitations

**Primary Key:** `invitation_id`

**Functional Dependency:**

`invitation_id → sender_id, recipient_id, note, sent_at, status, responded_at`

**Normal Form:** 3NF / BCNF

Each invitation has a unique ID. Sender and recipient are references to the Members table.

Invitation information is stored independently from accepted connections.

### 3.9 Jobs

**Primary Key:** `job_id`

**Functional Dependency:**

`job_id → company_id, title, city_id, workplace_type, employment_type, min_experience, min_salary_lpa, max_salary_lpa, posted_at, closes_at, status`

**Normal Form:** 3NF / BCNF

Each job posting is identified by its job ID. Company and city details are referenced using foreign keys.

Salary and location information belongs to the job posting itself.

### 3.10 Job Skills

**Composite Primary Key:** `(job_id, skill_id)`

**Functional Dependency:**

`(job_id, skill_id) → no additional non-key attributes`

**Normal Form:** 3NF / BCNF

This table connects jobs with the skills required for them. The composite primary key prevents the same skill from being unnecessarily repeated for the same job.

### 3.11 Applications

**Primary Key:** `application_id`

**Additional Unique Constraint:** `(job_id, member_id)`

**Functional Dependencies:**

`application_id → job_id, member_id, applied_at, easy_apply, status, status_updated_at`

`(job_id, member_id) → application_id, applied_at, easy_apply, status, status_updated_at`

**Normal Form:** 3NF / BCNF

Each application has a unique application ID. The combination of job ID and member ID is also unique because a member should not apply to the same job more than once.

Job and member information is referenced using foreign keys.

### 3.12 Profile Views

**Primary Key:** `view_id`

**Functional Dependency:**

`view_id → viewer_id, viewed_id, viewed_at`

**Normal Form:** 3NF / BCNF

Each profile view is identified by a unique view ID.

The viewer ID may be NULL when a person views a profile using private mode. The viewed member is referenced through `viewed_id`.

## 4. Normalization Rules Applied

### First Normal Form (1NF)

A table satisfies 1NF when:

- Every column contains atomic values.
- There are no repeating groups.
- Each record can be uniquely identified.

**Application in this project:**

- Member information is stored in individual columns.
- Skills are separated into the `skills` table.
- Member-skill relationships are stored in `member_skills`.
- Job-skill relationships are stored in `job_skills`.
- Multiple work experiences are stored as separate records in `positions`.

Therefore, the tables are designed to satisfy 1NF.

### Second Normal Form (2NF)

A table satisfies 2NF when:

- It is already in 1NF.
- Every non-key attribute depends on the entire candidate key.
- There are no partial dependencies.

**Application in this project:**

The tables with composite primary keys are:

- `member_skills`
- `connections`
- `job_skills`

In `member_skills`, the endorsement count depends on the combination of member ID and skill ID.

In `connections`, the connection timestamp depends on the complete member pair.

In `job_skills`, there are no additional non-key attributes.

Therefore, these tables avoid partial dependencies.

Tables with single-column primary keys do not have partial dependencies on their primary keys.

### Third Normal Form (3NF)

A table satisfies 3NF when:

- It is already in 2NF.
- There are no transitive dependencies of non-prime attributes on candidate keys.

**Application in this project:**

- City details are stored in `cities`.
- Company details are stored in `companies`.
- Skill details are stored in `skills`.
- Member details are stored in `members`.
- Job details are stored in `jobs`.

Other tables reference these entities using foreign keys.

This avoids storing the same city, company, skill, or member details repeatedly.

Therefore, the design aims to satisfy 3NF.

### Boyce-Codd Normal Form (BCNF)

A table satisfies BCNF when every determinant in a non-trivial functional dependency is a superkey.

The functional dependencies listed for the project tables have primary keys or declared candidate keys as their determinants.

Therefore, the tables are expected to satisfy BCNF, provided the stated keys and uniqueness constraints are enforced and no additional functional dependencies exist in the data.

## 5. Derived and Redundant Columns

Some columns may contain information that can be obtained from other tables or attributes.

### 5.1 Current Company of a Member

A member's current company can be derived from the `positions` table.

The current position is identified by:

`end_date IS NULL`

The company can then be obtained using `company_id`.

Therefore, storing a separate current company ID in the `members` table would duplicate information.

**Decision:** Do not store a separate current company column in `members`. Derive it from `positions`.

This assumes the business rules allow at most one current position per member.

### 5.2 Members Headline

The `headline` column in the `members` table may contain information similar to the member's current position.

However, a headline is a user-written professional description and does not necessarily match the current position title or company.

For example, a member may write "Aspiring Software Engineer" even if their current position is different.

**Decision:** Keep the `headline` column because it is independent profile information and is not necessarily derivable from `positions`.

### 5.3 City Information

City names and state names are stored in the `cities` table.

Members, companies, and jobs store only their respective city IDs.

**Decision:** This avoids repeating city names and state information across multiple tables.

### 5.4 Company Information

Company details are stored in the `companies` table.

Positions and jobs store only `company_id`.

**Decision:** Company information is not duplicated in the positions and jobs tables.

### 5.5 Skill Information

Skill names are stored in the `skills` table.

The `member_skills` and `job_skills` tables store only skill IDs.

**Decision:** This avoids repeating skill names and maintains consistency.

## 6. Summary of Normal Forms

| Table | Primary Key | Normal Form |
|---|---|---|
| cities | city_id | 3NF / BCNF |
| members | member_id | 3NF / BCNF |
| companies | company_id | 3NF / BCNF |
| positions | position_id | 3NF / BCNF |
| skills | skill_id | 3NF / BCNF |
| member_skills | member_id, skill_id | 3NF / BCNF |
| connections | member_a, member_b | 3NF / BCNF |
| invitations | invitation_id | 3NF / BCNF |
| jobs | job_id | 3NF / BCNF |
| job_skills | job_id, skill_id | 3NF / BCNF |
| applications | application_id | 3NF / BCNF |
| profile_views | view_id | 3NF / BCNF |

## 7. Conclusion

The LinkedIn Professional Networking and Jobs Database uses a normalized relational structure.

The database separates independent entities such as members, companies, cities, and skills into different tables. Relationship tables handle many-to-many relationships, while primary keys and foreign keys maintain data integrity.

The design aims to satisfy 3NF and BCNF, reducing unnecessary duplication and preventing insertion, update, and deletion anomalies.

Derived information, such as a member's current company, is obtained through relationships rather than stored redundantly. Independent information, such as a member's headline, is retained.