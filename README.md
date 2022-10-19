# Field Server Panel

## Dependencies

* [Borg backup](https://borgbackup.readthedocs.io)
* [ngrok](https://ngrok.io), properly configured

## Development

Get a small USB stick; format and mount it. This is your backup partition.

Make a source directory either in the project directory at `/source` (recommended for development, that folder is gitignored) or elsewhere. Put some random files in it.

Grant passwordless sudo access for the ngrok wrapper script, e.g.:

    deploy ALL=(ALL) NOPASSWD: /path/to/field-server-panel/scripts/runngrok

Setup config with:

    cp config.yml.example config.yml

and edit to replace placeholders.

Run:

    ruby app.rb

and visit http://localhost:4567/ to verify it's working.

## Production

Similar to above, but with 'real' partitions, set up Passenger or other app server to serve Rack app.

### Upgrading

1. `git pull`
1. `bundle install`
