Self-Hosting with Docker

Learn how to configure and deploy Supabase with Docker.

Docker is the easiest way to get started with self-hosted Supabase. It should only take you a few minutes to get up and running. This guide assumes you are running the command from the machine you intend to host from.

Contents#
Before you begin
Installing and running Supabase
Accessing your services
Updating your services
Securing your services
Before you begin#
You need the following installed in your system: Git and Docker (Windows, macOS, or Linux).

Installing and running Supabase#
Follow these steps to start Supabase on your machine:


General

Advanced
# Get the code
git clone --depth 1 https://github.com/supabase/supabase
# Make your new supabase project directory
mkdir supabase-project
# Tree should look like this
# .
# ├── supabase
# └── supabase-project
# Copy the compose files over to your project
cp -rf supabase/docker/* supabase-project
# Copy the fake env vars
cp supabase/docker/.env.example supabase-project/.env
# Switch to your project directory
cd supabase-project
# Pull the latest images
docker compose pull
# Start the services (in detached mode)
docker compose up -d
If you are using rootless docker, edit .env and set DOCKER_SOCKET_LOCATION to your docker socket location. For example: /run/user/1000/docker.sock. Otherwise, you will see an error like container supabase-vector exited (0).

After all the services have started you can see them running in the background:

docker compose ps
All of the services should have a status running (healthy). If you see a status like created but not running, try starting that service manually with docker compose start <service-name>.

Your app is now running with default credentials.
Secure your services as soon as possible using the instructions below.

Accessing Supabase Studio#
You can access Supabase Studio through the API gateway on port 8000. For example: http://<your-ip>:8000, or localhost:8000 if you are running Docker locally.

You will be prompted for a username and password. By default, the credentials are:

Username: supabase
Password: this_password_is_insecure_and_should_be_updated
You should change these credentials as soon as possible using the instructions below.

Accessing the APIs#
Each of the APIs are available through the same API gateway:

REST: http://<your-ip>:8000/rest/v1/
Auth: http://<your-domain>:8000/auth/v1/
Storage: http://<your-domain>:8000/storage/v1/
Realtime: http://<your-domain>:8000/realtime/v1/
Accessing your Edge Functions#
Edge Functions are stored in volumes/functions. The default setup has a hello Function that you can invoke on http://<your-domain>:8000/functions/v1/hello.

You can add new Functions as volumes/functions/<FUNCTION_NAME>/index.ts. Restart the functions service to pick up the changes: docker compose restart functions --no-deps

Accessing Postgres#
By default, the Supabase stack runs the Supavisor connection pooler. Supavisor provides efficient management of database connections.

You can connect to the Postgres database using the following methods:

For session-based connections (equivalent to direct Postgres connections):
psql 'postgres://postgres.your-tenant-id:your-super-secret-and-long-postgres-password@localhost:5432/postgres'
For pooled transactional connections:
psql 'postgres://postgres.your-tenant-id:your-super-secret-and-long-postgres-password@localhost:6543/postgres'
The default tenant ID is your-tenant-id, and the default password is your-super-secret-and-long-postgres-password. You should change these as soon as possible using the instructions below.

By default, the database is not accessible from outside the local machine but the pooler is. You can change this by updating the docker-compose.yml file.

You may also want to connect to your Postgres database via an ORM or another direct method other than psql.

For this you can use the standard Postgres connection string.
You can find the the environment values mentioned below in the .env file which will be covered in the next section.

postgres://postgres:[POSTGRES_PASSWORD]@[your-server-ip]:5432/[POSTGRES_DB]
Updating your services#
For security reasons, we "pin" the versions of each service in the docker-compose file (these versions are updated ~monthly). If you want to update any services immediately, you can do so by updating the version number in the docker compose file and then running docker compose pull. You can find all the latest docker images in the Supabase Docker Hub.

You should update your services frequently to get the latest features and bug fixes and security patches. Note that you will need to restart the services to pick up the changes, which will result in some downtime for your services.

Example
You'll want to update the Studio(Dashboard) frequently to get the latest features and bug fixes. To update the Dashboard:

Visit the supabase/studio image in the Supabase Docker Hub
Find the latest version (tag) number. It will look something like 20241029-46e1e40
Update the image field in the docker-compose.yml file to the new version. It should look like this: image: supabase/studio:20241028-a265374
Run docker compose pull and then docker compose up -d to restart the service with the new version.
Securing your services#
While we provided you with some example secrets for getting started, you should NEVER deploy your Supabase setup using the defaults we have provided. Follow all of the steps in this section to ensure you have a secure setup, and then restart all services to pick up the changes.

Generate API keys#
We need to generate secure keys for accessing your services. We'll use the JWT Secret to generate anon and service API keys using the form below.

Obtain a Secret: Use the 40-character secret provided, or create your own. If creating, ensure it's a strong, random string of 40 characters.
Store Securely: Save the secret in a secure location on your local machine. Don't share this secret publicly or commit it to version control.
Generate a JWT: Use the form below to generate a new JWT using your secret.
JWT Secret:
JAaPnBdSee0c7nZCtbVISd6DXLE61YHlsUXL663a
Key:

ANON_KEY
The JWT will be generated from this info:
{
  "role": "anon",
  "iss": "supabase",
  "iat": 1760842800,
  "exp": 1918609200
}

Generate JWT
Update API keys#
Run this form twice to generate new anon and service API keys. Replace the values in the ./docker/.env file:

ANON_KEY - replace with an anon key
SERVICE_ROLE_KEY - replace with a service key
You will need to restart the services for the changes to take effect.

Update secrets#
Update the ./docker/.env file with your own secrets. In particular, these are required:

POSTGRES_PASSWORD: the password for the postgres role.
JWT_SECRET: used by PostgREST and GoTrue, among others.
SITE_URL: the base URL of your site.
SMTP_*: mail server credentials. You can use any SMTP server.
POOLER_TENANT_ID: the tenant-id that will be used by Supavisor pooler for your connection string
PG_META_CRYPTO_KEY: encryption key for securing connection strings between Studio and postgres-meta
SECRET_KEY_BASE: encryption key for securing Realtime and Supavisor communications. (Must be at least 64 characters; generate with openssl rand -base64 48)
You will need to restart the services for the changes to take effect.

Dashboard authentication#
The Dashboard is protected with basic authentication. The default user and password MUST be updated before using Supabase in production.
Update the following values in the ./docker/.env file:

DASHBOARD_USERNAME: The default username for the Dashboard
DASHBOARD_PASSWORD: The default password for the Dashboard
You can also add more credentials for multiple users in ./docker/volumes/api/kong.yml. For example:

basicauth_credentials:
  - consumer: DASHBOARD
    username: user_one
    password: password_one
  - consumer: DASHBOARD
    username: user_two
    password: password_two
To enable all dashboard features outside of localhost, update the following value in the ./docker/.env file:

SUPABASE_PUBLIC_URL: The URL or IP used to access the dashboard
You will need to restart the services for the changes to take effect.

Restarting all services#
You can restart services to pick up any configuration changes by running:

# Stop and remove the containers
docker compose down
# Recreate and start the containers
docker compose up -d
Be aware that this will result in downtime. Simply restarting the services does not apply configuration changes.

Stopping all services#
You can stop Supabase by running docker compose stop in same directory as your docker-compose.yml file.

Uninstalling#
You can stop Supabase by running the following in same directory as your docker-compose.yml file:

# Stop docker and remove volumes:
docker compose down -v
# Remove Postgres data:
rm -rf volumes/db/data/
This will destroy all data in the database and storage volumes, so be careful!

Managing your secrets#
Many components inside Supabase use secure secrets and passwords. These are listed in the self-hosting env file, but we strongly recommend using a secrets manager when deploying to production. Plain text files like dotenv lead to accidental costly leaks.

Some suggested systems include:

Doppler
Infisical
Key Vault by Azure (Microsoft)
Secrets Manager by AWS
Secrets Manager by GCP
Vault by HashiCorp
Advanced#
Everything beyond this point in the guide helps you understand how the system works and how you can modify it to suit your needs.

Architecture#
Supabase is a combination of open source tools, each specifically chosen for Enterprise-readiness.

If the tools and communities already exist, with an MIT, Apache 2, or equivalent open license, we will use and support that tool.
If the tool doesn't exist, we build and open source it ourselves.

Diagram showing the architecture of Supabase. The Kong API gateway sits in front of 7 services: GoTrue, PostgREST, Realtime, Storage, pg_meta, Functions, and pg_graphql. All the services talk to a single Postgres instance.
Kong is a cloud-native API gateway.
GoTrue is an JWT based API for managing users and issuing JWT tokens.
PostgREST is a web server that turns your Postgres database directly into a RESTful API
Realtime is an Elixir server that allows you to listen to Postgres inserts, updates, and deletes using WebSockets. Realtime polls Postgres' built-in replication functionality for database changes, converts changes to JSON, then broadcasts the JSON over WebSockets to authorized clients.
Storage provides a RESTful interface for managing Files stored in S3, using Postgres to manage permissions.
postgres-meta is a RESTful API for managing your Postgres, allowing you to fetch tables, add roles, and run queries, etc.
Postgres is an object-relational database system with over 30 years of active development that has earned it a strong reputation for reliability, feature robustness, and performance.
Supavisor is a scalable connection pooler for Postgres, allowing for efficient management of database connections.
For the system to work cohesively, some services require additional configuration within the Postgres database. For example, the APIs and Auth system require several default roles and the pgjwt Postgres extension.

You can find all the default extensions inside the schema migration scripts repo. These scripts are mounted at /docker-entrypoint-initdb.d to run automatically when starting the database container.

Configuring services#
Each system has a number of configuration options which can be found in the relevant product documentation.

Postgres
PostgREST
Realtime
Auth
Storage
Kong
Supavisor
These configuration items are generally added to the env section of each service, inside the docker-compose.yml section. If these configuration items are sensitive, they should be stored in a secret manager or using an .env file and then referenced using the ${} syntax.


docker-compose.yml

.env
services:
  rest:
    image: postgrest/postgrest
    environment:
      PGRST_JWT_SECRET: ${JWT_SECRET}
Common configuration#
Each system can be configured independently. Some of the most common configuration options are listed below.

Configuring an email server#
You will need to use a production-ready SMTP server for sending emails. You can configure the SMTP server by updating the following environment variables:

SMTP_ADMIN_EMAIL=
SMTP_HOST=
SMTP_PORT=
SMTP_USER=
SMTP_PASS=
SMTP_SENDER_NAME=
We recommend using AWS SES. It's extremely cheap and reliable. Restart all services to pick up the new configuration.

Configuring S3 Storage#
By default all files are stored locally on the server. You can configure the Storage service to use S3 by updating the following environment variables:

storage:
  environment: STORAGE_BACKEND=s3
    GLOBAL_S3_BUCKET=name-of-your-s3-bucket
    REGION=region-of-your-s3-bucket
You can find all the available options in the storage repository. Restart the storage service to pick up the changes: docker compose restart storage --no-deps

Configuring Supabase AI Assistant#
Configuring the Supabase AI Assistant is optional. By adding your own OPENAI_API_KEY, you can enable AI services, which help with writing SQL queries, statements, and policies.


docker-compose.yml

.env
services:
  studio:
    image: supabase/studio
    environment:
      OPENAI_API_KEY: ${OPENAI_API_KEY:-}
Setting database's log_min_messages#
By default, docker compose sets the database's log_min_messages configuration to fatal to prevent redundant logs generated by Realtime. You can configure log_min_messages using any of the Postgres Severity Levels.

Accessing Postgres through Supavisor#
By default, the Postgres database is accessible through the Supavisor connection pooler. This allows for more efficient management of database connections. You can connect to the pooled database using the POOLER_PROXY_PORT_TRANSACTION port and POSTGRES_PORT for session based connections.

For more information on configuring and using Supavisor, see the Supavisor documentation.

Exposing your Postgres database#
If you need direct access to the Postgres database without going through Supavisor, you can expose it by updating the docker-compose.yml file:

# Comment or remove the supavisor section of the docker-compose file
#  supavisor:
#    ports:
# ...
db:
  ports:
    - ${POSTGRES_PORT}:${POSTGRES_PORT}
This is less-secure, so make sure you are running a firewall in front of your server.

File storage backend on macOS#
By default, Storage backend is set to file, which is to use local files as the storage backend. For macOS compatibility, you need to choose VirtioFS as the Docker container file sharing implementation (in Docker Desktop -> Preferences -> General).

Setting up logging with the Analytics server#
Additional configuration is required for self-hosting the Analytics server. For the full setup instructions, see Self Hosting Analytics.

Upgrading Analytics#
Due to the changes in the Analytics server, you will need to run the following commands to upgrade your Analytics server:

All data in analytics will be deleted when you run the commands below.

### Destroy analytics to transition to postgres self hosted solution without other data loss
# Enter the container and use your .env POSTGRES_PASSWORD value to login
docker exec -it $(docker ps | grep supabase-db | awk '{print $1}') psql -U supabase_admin --password
# Drop all the data in the _analytics schema
DROP PUBLICATION logflare_pub; DROP SCHEMA _analytics CASCADE; CREATE SCHEMA _analytics;\q
# Drop the analytics container
docker rm supabase-analytics
Demo#
A minimal setup working on Ubuntu, hosted on DigitalOcean.


Demo using DigitalOcean#
A DigitalOcean Droplet with 1 GB memory and 25 GB solid-state drive (SSD) is sufficient to start
To access the Dashboard, use the ipv4 IP address of your Droplet.
If you're unable to access Dashboard, run docker compose ps to see if the Studio service is running and healthy.
