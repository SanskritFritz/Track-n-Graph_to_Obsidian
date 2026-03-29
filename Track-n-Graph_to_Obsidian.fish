#!/usr/bin/env fish

# Import [Track & Graph](https://github.com/SamAmco/track-and-graph) data to Obsidian or CSV file.
# Generate notes with properties, one for each data point.
# File name is the datetime of a data point.
# Properties set:
#     TnG_Tracker(text)
#     TnG_TrackTime(datetime)
#     TnG_Value (number)
#     TnG_Label(text)
#     TnG_Note(text)
#
# Alternatively a csv file can be written instead of Obsidian,
# which then can be imported into Obsidian via its import plugin.
# This is recommended for an initial mass import, since it's **much** faster.
#
# For usage: --help
# Enjoy!
#     SanskritFritz (gmail)

# TODO
# • also filter for labels and notes
# • error detection for Obsidian calls

# Defaults:
set TrackAndGraphBackup_db "TrackAndGraphBackup.db"
set NotePath "Data/Track-n-Graph"

argparse 'd/database=' 't/tracker=+' 'min-time=' 'max-time=' 'dry-run' 'h/help' 'csv=' -- $argv
or return

if set --query _flag_help
	echo "Usage:"
	echo (status --current-filename)" \\"
	echo "    [-d|--database=<path/to/TrackAndGraphBackup.db>] \\"
	echo "    [-t|--tracker=<tracker> [...]] \\"
	echo "    [--min-time=<datetime>] [--max-time=<datetime>] \\"
	echo "    [--csv=<path/to/output.csv>]"
	echo "    [--dry-run] \\"
	echo "    [-h|--help]"
	echo
	echo "Example:"
	echo (status --current-filename)" \\"
	echo "    --database='/home/user/backup/android/TrackAndGraphBackup.db' \\"
	echo "    --tracker='Meat' --tracker='Vegetables' \\"
	echo "    --min-time='-3 days 0' --max-time='today 0'"
	echo
	echo "Database name defaults to 'TrackAndGraphBackup.db'."
	echo "Min/max time values are validated with 'date -d'".
	echo
	echo "Obsidian path is determined by the note property 'TnG_ROOT: true'"
	echo "where the path is derived from that note's path."
	echo "If missing, it defaults to 'Data/Track-n-Graph'."
	echo
	echo "With the option --csv ONLY the csv file will be written."
	echo
	return
end

set ValueError 0

if set --query _flag_database
	set TrackAndGraphBackup_db $_flag_database
end
if not test -f $TrackAndGraphBackup_db
	echo "Error: unable to find '$TrackAndGraphBackup_db'!"
	set ValueError 1
end

if set --query _flag_csv
and not set --query _flag_dry_run
and not touch "$_flag_csv" 2>/dev/null
	echo "Error: invalid csv file name: '$_flag_csv'!"
	set ValueError 1
end

set TrackersProvided 0
set TrackersSQL ""
set Trackers ""
set i 1
while set --query _flag_tracker[$i]
	if string match --regex --quiet '^[a-zA-Z0-9_]+$' $_flag_tracker[$i]
		set Trackers "$Trackers,'$_flag_tracker[$i]'"
	else
		echo "Error: the value '$_flag_tracker[$i]' is not allowed for -t|--tracker!"
		set ValueError 1
	end
	set TrackersProvided 1
	set i (math $i +1)
end

if test $TrackersProvided -eq 1
	set TrackersSQL "AND (tracker in ("(string sub -s 2 $Trackers)"))"
end

set MinTime ""
if set --query _flag_min_time
	set MinTime (date -d "$_flag_min_time" +'%Y-%m-%dT%H:%M:%S' 2>/dev/null)
	if not test -z $MinTime
		set MinTimeSQL "AND (track_time >= '$MinTime')"
	else
		echo "Error: the value '$_flag_min_time' is not allowed for --min-time!"
		set ValueError 1
	end
end

set MaxTime ""
if set --query _flag_max_time
	set MaxTime (date -d "$_flag_max_time" +'%Y-%m-%dT%H:%M:%S' 2>/dev/null)
	if not test -z $MaxTime
		set MaxTimeSQL "AND (track_time <= '$MaxTime')"
	else
		echo "Error: the value '$_flag_max_time' is not allowed for --max-time!"
		set ValueError 1
	end
end

# Exit if any error occured
if test $ValueError -eq 1; return 1; end

# The checks above made sure all parameters are SQL-injection-safe
set SQLquery "
SELECT tracker, track_time, value, label, note, file_name FROM (
	SELECT
		f.name as tracker,
		dp.epoch_milli as epoch,
		strftime('%Y-%m-%dT%H:%M:%S', DATETIME(ROUND(dp.epoch_milli/1000), 'unixepoch')) as track_time,
		dp.value,
		dp.label,
		dp.note,
		strftime('%Y-%m-%d %H.%M.%S', DATETIME(ROUND(dp.epoch_milli/1000), 'unixepoch')) as file_name
	FROM data_points_table dp
	JOIN features_table f on dp.feature_id = f.id
)
WHERE 1=1
	$TrackersSQL
	$MinTimeSQL
	$MaxTimeSQL
ORDER BY epoch desc
"
if set --query _flag_dry_run
	echo "-- DRY RUN --"
	echo $SQLquery
end;

if set --query _flag_csv
	echo csv file: $_flag_csv
	set csvRow 'TnG_Tracker,TnG_TrackTime,TnG_Value,TnG_Label,TnG_Note'
	if not set --query _flag_dry_run
		echo $csvRow > $_flag_csv
	else
		echo $csvRow
	end
else
	set RootNote (obsidian search query='["TnG_ROOT":true]' | string collect)
	if test (echo $RootNote | wc -l) -gt 1
		echo 'Error: ["TnG_ROOT":true] defined more than once in the vault.'
		return 1
	end
	if test $RootNote != "No matches found."
		set NotePath (dirname $RootNote)
	end

	set VaultRoot (obsidian vault info=path)
end

echo $SQLquery | sqlite3 $TrackAndGraphBackup_db |
while read ResultLine
	set ResultFields (string split "|" $ResultLine)
	set TnG_Tracker    $ResultFields[1]
	set TnG_TrackTime  $ResultFields[2]
	set TnG_Value      $ResultFields[3]
	set TnG_Label      $ResultFields[4]
	set TnG_Note       $ResultFields[5]
	set NoteName       $ResultFields[6]

	if set --query _flag_csv
		set csvRow '"'$TnG_Tracker'",'$TnG_TrackTime','$TnG_Value',"'$TnG_Label'","'$TnG_Note'"'
		if not set --query _flag_dry_run
			echo $csvRow >> $_flag_csv
		else
			echo $csvRow
		end
	else
		begin
		if not set --query _flag_dry_run
			if not test -f "$VaultRoot/$NotePath/$NoteName.md"
				# '< /dev/null' is necessary because otherwise Obsidian messes the STDOUT while loop
				obsidian create path="$NotePath/$NoteName.md" < /dev/null
			end
			obsidian property:set name="TnG_Tracker"   value="$TnG_Tracker"   type=text     path="$NotePath/$NoteName.md" < /dev/null
			obsidian property:set name="TnG_TrackTime" value="$TnG_TrackTime" type=datetime path="$NotePath/$NoteName.md" < /dev/null
			obsidian property:set name="TnG_Value"     value="$TnG_Value"     type=number   path="$NotePath/$NoteName.md" < /dev/null
			obsidian property:set name="TnG_Label"     value="$TnG_Label"     type=text     path="$NotePath/$NoteName.md" < /dev/null
			obsidian property:set name="TnG_Note"      value="$TnG_Note"      type=text     path="$NotePath/$NoteName.md" < /dev/null
		else
			echo "create path='$NotePath/$NoteName.md'"
			echo "property:set name='TnG_Tracker' value='$TnG_Tracker' type=text path='$NotePath/$NoteName.md'"
			echo "property:set name='TnG_TrackTime' value='$TnG_TrackTime' type=datetime path='$NotePath/$NoteName.md'"
			echo "property:set name='TnG_Value' value='$TnG_Value' type=number path='$NotePath/$NoteName.md'"
			echo "property:set name='TnG_Label' value='$TnG_Label' type=text path='$NotePath/$NoteName.md'"
			echo "property:set name='TnG_Note' value='$TnG_Note' type=text path='$NotePath/$NoteName.md'"
		end
		end
	end
end
