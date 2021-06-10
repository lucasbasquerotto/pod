-- Create the database
CREATE EXTENSION IF NOT EXISTS dblink;

DO $$
BEGIN
    PERFORM dblink_exec('', 'CREATE DATABASE {{ params.db_name }}');
EXCEPTION
    WHEN duplicate_database THEN
        RAISE NOTICE '%, skipping', SQLERRM USING ERRCODE = SQLSTATE;
END
$$;

-- Create Read-Only user
DO $$
BEGIN
    CREATE ROLE viewer WITH LOGIN PASSWORD '{{ params.viewer_password }}' NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION VALID UNTIL 'infinity';
EXCEPTION
    WHEN duplicate_object THEN
        RAISE NOTICE 'not creating role viewer -- it already exists';
END$$;

-- Assign permission to this read only user to the database postgres
GRANT CONNECT ON DATABASE postgres TO viewer;
\connect postgres;
GRANT USAGE ON SCHEMA public TO viewer;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO viewer;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO viewer;
-- Assign permissions to read all newly tables created in the future
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO viewer;

-- Assign permission to this read only user to the database {{ params.db_name }}
GRANT CONNECT ON DATABASE {{ params.db_name }} TO viewer;
\connect  {{ params.db_name }};
GRANT USAGE ON SCHEMA public TO viewer;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO viewer;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO viewer;
-- Assign permissions to read all newly tables created in the future
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO viewer;

-- {{ params.db_user }} user
DO $$
BEGIN
    CREATE ROLE {{ params.db_user }} WITH LOGIN PASSWORD '{{ params.db_password }}';
EXCEPTION
    WHEN duplicate_object THEN
        RAISE NOTICE 'not creating role {{ params.db_user }} -- it already exists';
END$$;

-- Assign permission to the {{ params.db_user }} user to the database {{ params.db_name }}
GRANT CONNECT ON DATABASE {{ params.db_name }} TO {{ params.db_user }};
\connect  {{ params.db_name }};
GRANT USAGE ON SCHEMA public TO {{ params.db_user }};
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO {{ params.db_user }};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO {{ params.db_user }};
-- Assign permissions to read all newly tables created in the future
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO {{ params.db_user }};
