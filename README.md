# Track & Graph to Obsidian


A Bash script to export [Track & Graph](https://samamco.github.io/track-and-graph/) backup data points to [Obsidian](https://obsidian.md/) or CSV.

Generate notes with properties, one for each data point.
File name is the datetime of a data point.
Properties set:
- TnG_Tracker (*text*)
- TnG_TrackTime (*datetime*)
- TnG_Value (*number*)
- TnG_Label (*text*)
- TnG_Note (*text*)

Alternatively CSV output can be redirected to a file,
which can be imported into Obsidian via its import plugin.
This is recommended for an initial mass import, since it's **much** faster,
but it creates duplicates when importing data points already present.
The advantage of direct write is that it doesn't duplicate data points,
but overwrites them, which is useful if a data point has been changed.
Obsidian is courteous enough not to change a note if the same data is written,
so the last modification date of the file remains the same.


```
./Track-n-Graph_to_Obsidian.sh --help

        Usage:
        ./Track-n-Graph_to_Obsidian.sh \
                [-d|--database=<path/to/TrackAndGraphBackup.db>] \
                [-t|--tracker=<tracker> [...]] \
                [--min-time=<datetime>] [--max-time=<datetime>] \
                [-o|obsidian-path=<obsidian/path/>] \
                [--csv] \
                [--dry-run] \
                [-h|--help]

        Example:
        ./Track-n-Graph_to_Obsidian.sh \
                --database='/backup/android/TrackAndGraphBackup.db' \
                --obsidian-path='Data/Track-n-Graph' \
                --tracker='Meat' --tracker='Vegetables' \
                --min-time='-3 days 0' --max-time='today 0'

        -d or --database is mandatory (this prevents accidental run)
        If no value is given, the name defaults to 'TrackAndGraphBackup.db'.

        Min/max time values are validated with 'date -d'.

        Obsidian path defaults to 'Data/Track-n-Graph'.

        With the option --csv ONLY the STDOUT will be written.
```
