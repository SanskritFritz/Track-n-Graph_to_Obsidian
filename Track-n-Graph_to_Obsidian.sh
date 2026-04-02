#!/bin/bash

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
# • Also filter for labels and notes
# • Error detection for Obsidian calls
# • Prevent accidental run by requiring an option
# • Make sure Obsidian GUI is already running

# Defaults:
TrackAndGraphBackup_db="TrackAndGraphBackup.db"
NotePath="Data/Track-n-Graph"

# Parse arguments
database=""
declare -a trackers
min_time=""
max_time=""
dry_run=false
csv_file=""
help=false

while [[ $# -gt 0 ]]; do
	case $1 in
		-d=*|--database=*)
			database="${1#*=}"
			shift 1
			;;
		-d|--database)
			database="$2"
			shift 2
			;;
		-t=*|--tracker=*)
			trackers+=("${1#*=}")
			shift 1
			;;
		-t|--tracker)
			trackers+=("$2")
			shift 2
			;;
		--min-time=*)
			min_time="${1#*=}"
			shift 1
			;;
		--min-time)
			min_time="$2"
			shift 2
			;;
		--max-time=*)
			max_time="${1#*=}"
			shift 1
			;;
		--max-time)
			max_time="$2"
			shift 2
			;;
		--csv=*)
			csv_file="${1#*=}"
			shift 1
			;;
		--csv)
			csv_file="$2"
			shift 2
			;;
		--dry-run)
			dry_run=true
			shift
			;;
		-h|--help)
			help=true
			shift
			;;
		*)
			echo "Unknown option: $1"
			exit 1
			;;
	esac
done

if [[ "$help" == true ]]; then
	echo "Usage:"
	echo "$(basename "$0") \\"
	echo "    [-d|--database=<path/to/TrackAndGraphBackup.db>] \\"
	echo "    [-t|--tracker=<tracker> [...]] \\"
	echo "    [--min-time=<datetime>] [--max-time=<datetime>] \\"
	echo "    [--csv=<path/to/output.csv>]"
	echo "    [--dry-run] \\"
	echo "    [-h|--help]"
	echo
	echo "Example:"
	echo "$(basename "$0") \\"
	echo "    --database='/home/user/backup/android/TrackAndGraphBackup.db' \\"
	echo "    --tracker='Meat' --tracker='Vegetables' \\"
	echo "    --min-time='-3 days 0' --max-time='today 0'"
	echo
	echo "Database name defaults to 'TrackAndGraphBackup.db'."
	echo "Min/max time values are validated with 'date -d'."
	echo
	echo "Obsidian path is determined by the note property 'TnG_ROOT: true'"
	echo "where the path is derived from that note's path."
	echo "If missing, it defaults to 'Data/Track-n-Graph'."
	echo
	echo "With the option --csv ONLY the csv file will be written."
	echo
	exit 0
fi

ValueError=0

if [[ -n "$database" ]]; then
	TrackAndGraphBackup_db="$database"
fi

if [[ ! -f "$TrackAndGraphBackup_db" ]]; then
	echo "Error: unable to find '$TrackAndGraphBackup_db'!" >&2
	ValueError=1
fi

if [[ -n "$csv_file" ]] && [[ "$dry_run" != true ]]; then
	if ! touch "$csv_file" 2>/dev/null; then
		echo "Error: invalid csv file name: '$csv_file'!" >&2
		ValueError=1
	fi
fi

# Build tracker SQL clause
TrackersProvided=0
TrackersSQL=""
Trackers=""

for tracker in "${trackers[@]}"; do
	if [[ $tracker =~ ^[a-zA-Z0-9_]+$ ]]; then
		Trackers="$Trackers,'$tracker'"
	else
		echo "Error: the value '$tracker' is not allowed for -t|--tracker!" >&2
		ValueError=1
	fi
	TrackersProvided=1
done

if [[ $TrackersProvided -eq 1 ]]; then
	TrackersSQL="AND (tracker in (${Trackers:1}))"
fi

# Build min time SQL clause
MinTime=""
MinTimeSQL=""
if [[ -n "$min_time" ]]; then
	MinTime=$(date -d "$min_time" +'%Y-%m-%dT%H:%M:%S' 2>/dev/null)
	if [[ "$MinTime" ]]; then
		MinTimeSQL="AND (track_time >= '$MinTime')"
	else
		echo "Error: the value '$min_time' is not allowed for --min-time!" >&2
		ValueError=1
	fi
fi

# Build max time SQL clause
MaxTime=""
MaxTimeSQL=""
if [[ -n "$max_time" ]]; then
	MaxTime=$(date -d "$max_time" +'%Y-%m-%dT%H:%M:%S' 2>/dev/null)
	if [[ "$MaxTime" ]]; then
		MaxTimeSQL="AND (track_time <= '$MaxTime')"
	else
		echo "Error: the value '$max_time' is not allowed for --max-time!" >&2
		ValueError=1
	fi
fi

# Exit if any error occurred
if [[ $ValueError -eq 1 ]]; then
	exit 1
fi

# The checks above made sure all parameters are SQL-injection-safe
read -r -d '' SQLquery << 'EOF'
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
EOF

if [[ "$dry_run" == true ]]; then
	echo "-- DRY RUN --"
	echo "$SQLquery"
fi

if [[ -n "$csv_file" ]]; then
	echo "csv file: $csv_file"
	csvRow='TnG_Tracker,TnG_TrackTime,TnG_Value,TnG_Label,TnG_Note'
	if [[ "$dry_run" != true ]]; then
		echo "$csvRow" > "$csv_file"
	else
		echo "$csvRow"
	fi
else
	RootNote=$(obsidian search query='["TnG_ROOT":true]' | tr '\n' ' ')
	RootNoteLineCount=$(echo "$RootNote" | wc -l)

	if [[ $RootNoteLineCount -gt 1 ]]; then
		echo 'Error: ["TnG_ROOT":true] defined more than once in the vault.' >&2
		exit 1
	fi

	if [[ "$RootNote" != "No matches found." ]]; then
		NotePath=$(dirname "$RootNote")
	fi

	VaultRoot=$(obsidian vault info=path)
fi

echo "$SQLquery" | sqlite3 "$TrackAndGraphBackup_db" |
while IFS='|' read -r TnG_Tracker TnG_TrackTime TnG_Value TnG_Label TnG_Note NoteName; do
	if [[ -n "$csv_file" ]]; then
		csvRow="\"$TnG_Tracker\",$TnG_TrackTime,$TnG_Value,\"$TnG_Label\",\"$TnG_Note\""
		if [[ "$dry_run" != true ]]; then
			echo "$csvRow" >> "$csv_file"
		else
			echo "$csvRow"
		fi
	else
		if [[ "$dry_run" != true ]]; then
			if [[ ! -f "$VaultRoot/$NotePath/$NoteName.md" ]]; then
				obsidian create path="$NotePath/$NoteName.md" < /dev/null
			fi
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
		fi
	fi
done
