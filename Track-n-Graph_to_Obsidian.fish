#!/usr/bin/env fish

# Import Track & Graph backup data to Obsidian
# Generate notes with properties, one for each data point
# File name is the datetime of a data point.
# Properties set:
#     TnG_tracker(text)
#     TnG_TrackTime(datetime)
#     TnG_Value (number)
#     TnG_Label(text)
#     TnG_Note(text)
#
# For usage: --help
# Enjoy!
#     SanskritFritz (gmail)

# TODO also filter via label and note

argparse 'd/database=' 't/tracker=+' 'min-date=' 'max-date=' 'dry-run' 'h/help'  -- $argv

if test $_flag_help
	echo "Usage:"
	echo (status --current-filename)" \\"
	echo "    [-d|--database=</absolute/path/to/TrackAndGraphBackup.db>] \\"
	echo "    [-t|--tracker=<tracker> [...]] \\"
	echo "    [--min-date=<YYYY-MM-DD>] [--max-date=<YYYY-MM-DD>] \\"
	echo "    [--dry-run] \\"
	echo "    [-h|--help]"
	echo
	echo "Example:"
	echo (status --current-filename)" \\"
	echo "    --database='/home/user/backup/android/TrackAndGraphBackup.db' \\"
	echo "    --tracker='Meat' --tracker='Vegetables' \\"
	echo "    --min-date='2026-01-01' --max-date='2026-02-01'"
	echo
	echo "All options are optional, if absent, all data points will be imported."
	echo
	echo "Obsidian path is determined by the property 'TnG_ROOT: true'"
	echo "or default to 'Data/Track-n-Graph'"
	echo
	return
end

set TrackAndGraphBackup_db "TrackAndGraphBackup.db"
if test $_flag_database
	set TrackAndGraphBackup_db $_flag_database
end

set TrackersProvided 0
set TrackersSQL ""
set Trackers ""
set ValueError 0
set i 1
while test $_flag_tracker[$i]
	if string match --regex --quiet '^[a-zA-Z0-9_]+$' $_flag_tracker[$i]
		set Trackers "$Trackers,'$_flag_tracker[$i]'"
	else
		echo "The value '$_flag_tracker[$i]' is not allowed for -t|--tracker!"
		set ValueError 1
	end
	set TrackersProvided 1
	set i (math $i +1)
end

if test $TrackersProvided -eq 1
	set TrackersSQL "AND (tracker in ("(string sub -s 2 $Trackers)"))"
end

set MinDate "''"
if set --query _flag_min_date
	set MinDate "'$_flag_min_date'"
	if not string match --regex --quiet '^\d{4}-\d{2}-\d{2}$' $_flag_min_date
		echo "The value '$_flag_min_date' is not allowed for --min-date!"
		set ValueError 1
	end
end

set MaxDate "''"
if set --query _flag_max_date
	set MaxDate "'$_flag_max_date'"
	if not string match --regex --quiet '^\d{4}-\d{2}-\d{2}$' $_flag_max_date
		echo "The value '$_flag_max_date' is not allowed for --max-date!"
		set ValueError 1
	end
end

if test $ValueError -eq 1; return 1; end

# The "string match" inspections above made sure the parameters are SQL-injection-safe
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
	AND ($MinDate = '' OR track_time >= $MinDate)
	AND ($MaxDate = '' OR track_time <= $MaxDate)
ORDER BY epoch desc
"
if test $_flag_dry_run
	echo "-- DRY RUN --"
	echo $SQLquery
end;

set VaultRoot (obsidian vault info=path)
set TnG_Path "Data/Track-n-Graph" # Default
set TnG_Path (dirname (obsidian search query='["TnG_ROOT":true]')) # Undefined if set more than once

echo $SQLquery | sqlite3 $TrackAndGraphBackup_db |
while read ResultLine
	echo $ResultLine
	set ResultFields (string split "|" $ResultLine)
	set TnG_Tracker    $ResultFields[1]
	set TnG_TrackTime  $ResultFields[2]
	set TnG_Value      $ResultFields[3]
	set TnG_Label      $ResultFields[4]
	set TnG_Note       $ResultFields[5]
	set TnG_FileName   $ResultFields[6]

	if not test $_flag_dry_run
		if not test -f "$VaultRoot/$TnG_Path/$TnG_FileName.md"
			obsidian create path="$TnG_Path/$TnG_FileName.md" < /dev/null
		end
		obsidian property:set name="TnG_tracker"   value="$TnG_Tracker"   type=text     path="$TnG_Path/$TnG_FileName.md" < /dev/null
		obsidian property:set name="TnG_TrackTime" value="$TnG_TrackTime" type=datetime path="$TnG_Path/$TnG_FileName.md" < /dev/null
		obsidian property:set name="TnG_Value"     value="$TnG_Value"     type=number   path="$TnG_Path/$TnG_FileName.md" < /dev/null
		obsidian property:set name="TnG_Label"     value="$TnG_Label"     type=text     path="$TnG_Path/$TnG_FileName.md" < /dev/null
		obsidian property:set name="TnG_Note"      value="$TnG_Note"      type=text     path="$TnG_Path/$TnG_FileName.md" < /dev/null
	else
		echo "create path='$TnG_Path/$TnG_FileName.md'"
		echo "property:set name='TnG_tracker' value='$TnG_Tracker' type=text path='$TnG_Path/$TnG_FileName.md'"
		echo "property:set name='TnG_TrackTime' value='$TnG_TrackTime' type=datetime path='$TnG_Path/$TnG_FileName.md'"
		echo "property:set name='TnG_Value' value='$TnG_Value' type=number path='$TnG_Path/$TnG_FileName.md'"
		echo "property:set name='TnG_Label' value='$TnG_Label' type=text path='$TnG_Path/$TnG_FileName.md'"
		echo "property:set name='TnG_Note' value='$TnG_Note' type=text path='$TnG_Path/$TnG_FileName.md'"
	end
end
