# sati-data

Repository for automated backup of the data for sati.stanford.edu.

A cron job on the production server runs once an hour and executes the [`sati-backup.sh`](sati-backup.sh) script. The script automatically commits to this repo if there are any changes to the user-generated content of the application (the `Items` and `User` database models, and uploaded Item images). The JSON files are pretty-printed for the sake of nice clean diffs (admittedly at the expense of _much_ larger file sizes).

The assets here ([`items.json`](items.json) and the files in [`media/`](media)) are immediately available as research outputs from the project.

They also serve as an hourly backup of data that cannot be recreated simply by bringing up the application and running the init process, and can be loaded into a running deploy of the application using Django's `loaddata` management command (and syncing the `media/` folder appropriately).

To load the data into an instance deployed with `docker-compose`, the following commands are suggested (from or with the docker-compose context):

```
$ docker-compose exec -T django python manage.py loaddata --format json - < /path/to/users.json

$ docker-compose exec -T django python manage.py loaddata --format json - < /path/to/items.json
```

## `sati-backup.sh` Usage

```
Usage: sati-backup.sh [-q]

  Backs up user data from the SATI application -- all the database data from the
  Items and Users apps, as well as the uploaded item images -- and commits new or
  modified data to GitHub.

    -h          display this help and exit
    -q          quiet operation; will only produce output in case of error
                (intended for use from cron)


Respects the following environment variables (the defaults are expected to be
used in production).

  BACKUP_DIR          Directory that contains the backup repo
                       - defaults to this script's parent dir
  COMPOSE_PROJ_DIR    Context directory for docker-compose
                       - defaults to $BACKUP_DIR/../sati
  COMPOSE_FILE        docker-compose configuration file
                       - defaults to $COMPOSE_PROJ_DIR/docker-compose.yml
  MEDIA_DIR           Directory that contains the item images (Django's MEDIA_ROOT)
                       - defaults to $COMPOSE_PROJ_DIR/media
  ENV_FILE            .env file passed both to docker-compose and to the containers
                       - defaults to $COMPOSE_PROJ_DIR/.env
```

## Installation

To install this script and repository in a production environment, the following steps are necessary:

1. Clone this repo to the production docker host.
1. Use `ssh-keygen` to create an SSH key-pair and upload the public key to GitHub as a deploy key for this repo.
1. Install a cron job to run the script with the desired frequency. e.g.:

   ```
   MAILTO=<email.address.for.errors@server.example>

   # docker-compose is executed on this box with python2.7 (since that's all that's installed), so DeprecationWarnings are raised
   PYTHONWARNINGS="ignore"

   # Check for updated content and commit it to GitHub
   @hourly  /path/to/repo/sati-backup.sh -q
   ```

   Note that much of the configuration for the script can be set with environment variables (see above), but the default values are expected to be appropriate for production environments.
