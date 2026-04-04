#!/usr/bin/env bash

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
# • CSV only to STDOUT

# Defaults:
TrackAndGraphBackup_db="TrackAndGraphBackup.db"
NotePath="Data/Track-n-Graph"

obsidian_running=false
for pid in $(pgrep electron); do
	# if grep --quiet "obsidian" /proc/$pid/cmdline 2>/dev/null; then
	if grep --quiet "obsidian" /proc/$pid/cmdline; then
		obsidian_running=true
	fi
done
if [[ $obsidian_running == false ]]; then
	echo "Please start Obsidian first!"
	exit 1
fi

# Parse arguments
database_file=""
declare -a trackers
min_time=""
max_time=""
csv_file=""
dry_run=false
help=false
error_happened=false

while [[ $# -gt 0 ]]; do
	case $1 in
		-d=*|--database=*)
			database_file="${1#*=}"
			if [[ -z "$database_file" ]]; then
				# no value given
				database_file="$TrackAndGraphBackup_db"
			fi
			shift 1
			;;
		-d|--database)
			if [[ -n "$2" && "$2" != -* ]]; then
				database_file="$2"
				shift 1
			else
				# no value given
				database_file="$TrackAndGraphBackup_db"
			fi
			shift 1
			;;
		-t=*|--tracker=*)
			tracker="${1#*=}"
			if [[ -n "$tracker" ]]; then
				# -t|--tracker can be given more than once, hence the `trackers` array
				trackers+=("$tracker")
			else
				echo "Error: value for -t|--tracker is mandatory!" >&2
				error_happened=true
			fi
			shift 1
			;;
		-t|--tracker)
			if [[ -n "$2" && "$2" != -* ]]; then
				trackers+=("$2")
				shift 1
			else
				echo "Error: value for -t|--tracker is mandatory!" >&2
				error_happened=true
			fi
			shift 1
			;;
		--min-time=*)
			min_time="${1#*=}"
			if [[ -z "$min_time" ]]; then
				echo "Error: value for --min-time is mandatory!" >&2
				error_happened=true
			fi
			shift 1
			;;
		--min-time)
			if [[ -n "$2" && "$2" != -* ]]; then
				min_time="$2"
				shift 1
			else
				echo "Error: value for --min-time is mandatory!" >&2
				error_happened=true
			fi
			shift 1
			;;
		--max-time=*)
			max_time="${1#*=}"
			if [[ -z "$min_time" ]]; then
				echo "Error: value for --max-time is mandatory!" >&2
				error_happened=true
			fi
			shift 1
			;;
		--max-time)
			if [[ -n "$2" && "$2" != -* ]]; then
				max_time="$2"
				shift 1
			else
				echo "Error: value for --max-time is mandatory!" >&2
				error_happened=true
			fi
			shift 1
			;;
		-o=*|--obsidian-path=*)
			NotePath="${1#*=}"
			if [[ -z "$NotePath" ]]; then
				echo "Error: value for -o|--obsidian-path is mandatory!" >&2
				error_happened=true
			fi
			shift 1
			;;
		-o=|--obsidian-path=)
			if [[ -n "$2" && "$2" != -* ]]; then
				NotePath="$2"
				shift 1
			else
				echo "Error: value for -o|--obsidian-path is mandatory!" >&2
				error_happened=true
			fi
			shift 1
			;;
		--csv=*)
			csv_file="${1#*=}"
			if [[ -z "$csv_file" ]]; then
				echo "Error: value for --csv is mandatory!" >&2
				error_happened=true
			fi
			shift 1
			;;
		--csv)
			if [[ -n "$2" && "$2" != -* ]]; then
				csv_file="$2"
				shift 1
			else
				echo "Error: value for --csv is mandatory!" >&2
				error_happened=true
			fi
			shift 1
			;;
		--dry-run)
			dry_run=true
			shift 1
			;;
		-h|--help)
			help=true
			shift 1
			;;
		*)
			echo "Error: unknown option: '$1'!" >&2
			error_happened=true
			shift 1
			;;
	esac
done

if [[ "$help" == true ]]; then
	usage="
	Usage:
	$0 \\
		[-d|--database=<path/to/TrackAndGraphBackup.db>] \\
		[-t|--tracker=<tracker> [...]] \\
		[--min-time=<datetime>] [--max-time=<datetime>] \\
		[-o|obsidian-path=<obsidian/path/>]
		[--csv=<path/to/output.csv>] \\
		[--dry-run] \\
		[-h|--help]

	Example:
	$0 \\
		--database='/backup/android/TrackAndGraphBackup.db' \\
		--obsidian-path='Data/Track-n-Graph'
		--tracker='Meat' --tracker='Vegetables' \\
		--min-time='-3 days 0' --max-time='today 0'

	-d or --database is mandatory (this prevents accidental run)
	If no value is given, the name defaults to '$TrackAndGraphBackup_db'.

	Min/max time values are validated with 'date -d'.

	Obsidian path defaults to '$NotePath'.

	With the option --csv ONLY the csv file will be written.
	"
	echo "$usage"
	exit 0
fi

if [[ -z "$database_file" ]]; then
	echo "Error: -d or --database is mandatory! This prevents accidental run." >&2
	error_happened=true
elif [[ ! -f "$database_file" ]]; then
	echo "Error: unable to find database '$database_file'!" >&2
	error_happened=true
fi

if [[ -n "$csv_file" ]] && [[ "$dry_run" != true ]]; then
	if ! touch "$csv_file" 2>/dev/null; then
		echo "Error: invalid csv file name: '$csv_file'!" >&2
		error_happened=true
	fi
fi

# Build tracker SQL clause
trackers_SQL=""
trackers_list=""

for tracker in "${trackers[@]}"; do
	if [[ $tracker =~ ^[a-zA-Z0-9_]+$ ]]; then
		trackers_list="$trackers_list,'$tracker'"
	else
		echo "Error: the value '$tracker' is not allowed for -t|--tracker!" >&2
		error_happened=true
	fi
done

if [[ -n $trackers_list ]]; then
	trackers_SQL="AND (tracker in (${trackers_list:1}))"
fi

# Build min time SQL clause
min_time_SQL=""
if [[ -n "$min_time" ]]; then
	min_time_ISO=$(date -d "$min_time" +'%Y-%m-%dT%H:%M:%S' 2>/dev/null)
	if [[ -n "$min_time_ISO" ]]; then
		min_time_SQL="AND (track_time >= '$min_time_ISO')"
	else
		echo "Error: the value '$min_time' is not allowed for --min-time!" >&2
		error_happened=true
	fi
fi

# Build max time SQL clause
max_time_SQL=""
if [[ -n "$max_time" ]]; then
	max_time_ISO=$(date -d "$max_time" +'%Y-%m-%dT%H:%M:%S' 2>/dev/null)
	if [[ "$max_time_ISO" ]]; then
		max_time_SQL="AND (track_time <= '$max_time_ISO')"
	else
		echo "Error: the value '$max_time' is not allowed for --max-time!" >&2
		error_happened=true
	fi
fi

# Exit if any error occurred
if [[ $error_happened == true ]]; then
	exit 1
fi

# The checks above made sure all parameters are SQL-injection-safe
SQLquery="
SELECT tracker, track_time, value, label, note, note_name FROM (
	SELECT
		f.name as tracker,
		dp.epoch_milli as epoch,
		strftime('%Y-%m-%dT%H:%M:%S', DATETIME(ROUND(dp.epoch_milli/1000), 'unixepoch')) as track_time,
		dp.value,
		dp.label,
		dp.note,
		strftime('%Y-%m-%d %H.%M.%S', DATETIME(ROUND(dp.epoch_milli/1000), 'unixepoch')) as note_name
	FROM data_points_table dp
	JOIN features_table f on dp.feature_id = f.id
)
WHERE 1=1
	$trackers_SQL
	$min_time_SQL
	$max_time_SQL
ORDER BY epoch desc"

if [[ "$dry_run" == true ]]; then
	echo "-- DRY RUN --"
	echo "$SQLquery"
fi

if [[ -n "$csv_file" ]]; then
	echo "CSV file: $csv_file"
	csv_row='TnG_Tracker,TnG_TrackTime,TnG_Value,TnG_Label,TnG_Note'
	if [[ "$dry_run" != true ]]; then
		echo "$csv_row" > "$csv_file"
	else
		echo "$csv_row"
	fi
else
	vaultroot_path=$(obsidian vault info=path)
fi

echo "$SQLquery" | sqlite3 "$TrackAndGraphBackup_db" |
while IFS='|' read -r TnG_Tracker TnG_TrackTime TnG_Value TnG_Label TnG_Note NoteName; do
	if [[ -n "$csv_file" ]]; then
		csv_row="\"$TnG_Tracker\",$TnG_TrackTime,$TnG_Value,\"$TnG_Label\",\"$TnG_Note\""
		if [[ "$dry_run" != true ]]; then
			echo "$csv_row" >> "$csv_file"
		else
			echo "$csv_row"
		fi
	else
		if [[ "$dry_run" != true ]]; then
			if [[ ! -f "$vaultroot_path/$NotePath/$NoteName.md" ]]; then
				# '< /dev/null' is necessary because otherwise Obsidian messes with the STDOUT while loop
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
