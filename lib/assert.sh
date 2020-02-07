#-----------------------------
# Depends on console.sh
#-----------------------------

ASSERT_FAIL_GENERIC_MESSAGE='Ocorreu um erro nao previsto. Este erro pode ser 
decorrente de indisponibilidade no ambiente ou um BUG neste script. Favor tentar 
novamente mais tarde, caso o erro persista, pedimos que seja informado a celula 
de arquitetura e/ou infraestrutura.'

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
		echo "assert-not-empty failed; '$variable_name' is empty or not defined." >&2
		caller 0 | \
			awk '{ print "Line number:", $1, "; function/subroutine:", $2, "; filename:", $3 }' | \
			tee >&2
		red "$ASSERT_FAIL_GENERIC_MESSAGE" >&2
		exit 45
	fi
}

function assert-success
{
	if "$@"
	then
		echo -n > /dev/null
	else
		echo "assert-success failed while executing '$@'; status code: $?." >&2
		caller 0 | \
			awk '{ print "Line number:", $1, "; function/subroutine:", $2, "; filename:", $3 }' | \
			tee >&2
		red "$ASSERT_FAIL_GENERIC_MESSAGE" >&2
		exit 46
	fi
}