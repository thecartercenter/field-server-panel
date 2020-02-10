# Field Server Admin

## Dependencies

* [Borg backup](https://borgbackup.readthedocs.io)

## Development

1. Get a USB stick and format and mount it. Need not be big. This is your backup partition.
1. Make a source directory either in the project or elsewhere on your drive. Put some random files in it.
1. `cp config.yml.example config.yml`. Enter source and destination paths.
1. `ruby app.rb`
1. Visit http://localhost:4567/
