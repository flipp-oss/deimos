# Running Integration Tests

This repo includes integration tests in the [spec/utils](spec/utils) directory.
Here, there are tests for more deimos features that include a database integration like
* [Database Poller](README.md#Database Poller)
* [Database Backend](docs/DATABASE_BACKEND.md)
* [Deadlock Retrying](lib/deimos/utils/deadlock_retry.rb)

You will need to set up the following databases to develop and create unit tests in these test suites.
* [SQLite](#SQLite)
* [MySQL](#MySQL)
* [PostgreSQL](#PostgreSQL)

### SQLite
This database is covered through the `sqlite3` gem. 

## MySQL
### Setting up a local MySQL server (Mac)
```bash
# Download MySQL (Optionally, choose a version you are comfortable with)
brew install mysql
# Start automatically after rebooting your machine
brew services start mysql

# Cleanup once you are done with MySQL
brew services stop mysql
```

## PostgreSQL
### Setting up a local PostgreSQL server (Mac)
```bash
# Install postgres if it's not already installed
brew install postgres

# Initialize and Start up postgres db
brew services start postgres
initdb /usr/local/var/postgres
# Create the default database and user
# Use the password "root"
createuser -s --password postgres

# Cleanup once done with Postgres
killall postgres
brew services stop postgres
```

## Running Integration Tests
You must specify the tag "integration" when running these these test suites.
This can be done through the CLI with the `--tag integration` argument.
```bash
rspec spec/utils/ --tag integration
```
