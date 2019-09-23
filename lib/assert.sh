
# Param variable_name
function assert-not-empty
{
	local variable_name="$1"

	if [ -z "$variable_name" ]
	then
		echo "assert-defined: missing argument variable_name." >&2
		exit 41
	fi

	if [ -z "${!variable_name}" ]
	then
		echo "assert failed; '$variable_name' is empty or not defined." >&2
		caller 0 | awk '{ print "Line number:", $1, "; function/subroutine:", $2, "; filename:", $3 }' | \
			tee >&2
		exit 45
	fi
}