#!/usr/bin/env bash
progname="$(basename "${0}")"

## debug trace / logging
DEBUGGING="DEBUG_${progname}"
DEBUG="${!DEBUGGING}"
[[ -n "${DEBUG}" ]] && {
    [[ "${DEBUG}" == "verbose" ]] && {
        set -o verbose
        set -o xtrace
    }
}

DEFAULT_HEADER="tlilley"
DEFAULT_FONT="Courier6"
DEFAULT_OUTPUT_FORMAT="PostScript"
DEFAULT_PAPERSIZE="A4"
DEFAULT_ORIENTATION="portrait"
DEFAULT_TABSIZE=4
DEFAULT_USE_COLOR=1
DEFAULT_COLORSCHEME="tlilley"

MERGED_OUTPUT_FILENAME="merged.pdf"

DEFAULT_SYNSCRIPT_BIN="${HOME}/.cargo/bin/synscript"
DEFAULT_SYNSCRIPT_SYNTAX_DIR="${HOME}/.config/synscript/syntaxes"
DEFAULT_SYNSCRIPT_THEME="${HOME}/.config/synscript/themes/base16-tripplilley.tmTheme"

# @@ HACK: suppress line numbers? (default is to use line numbers)
: ${LINE_NUMBERS:=yes}
[[ "${LINE_NUMBERS}" == "no" ]] && {
    unset LINE_NUMBERS
}

## default margins in PostScript points (1/72")
left=12
right=12
top=36
bottom=36


usage () {
    local msg="
Usage: ${progname} [options] [filename ...]

    -h      Display this help message
    -l lang Language to use for pretty-printing
    -l ?    List available languages for pretty-printing
    -m      Merge all inputs into one output file
    -o      Open PDF output files (e.g., using \`open\` on Mac)

If no language is given with the -l option, ${progname} defaults to enscript's
built-in behaviour, which is to defer to the 'states' program and its
\"educated guess.\""

    printf "%s\n" "${msg}"
}




## ----------------------------------------------------------------------
## ANSI text attribute and color helpers
## ----------------------------------------------------------------------
## @@ TODO: peel ANSI helpers out into a library, or find one

## ANSI text attributes
declare -r -i COLOR_CLEAR=0
declare -r -i COLOR_RESET=0
declare -r -i COLOR_BOLD=1
declare -r -i COLOR_DARK=2
declare -r -i COLOR_UNDERLINE=4
declare -r -i COLOR_UNDERSCORE=4
declare -r -i COLOR_BLINK=5
declare -r -i COLOR_REVERSE=7
declare -r -i COLOR_CONCEALED=8


## ANSI text foreground and background colors are monotonically
## increasing integers, so we can compute them.
declare -r -i OFFSET_FOREGROUND=30
declare -r -i OFFSET_BACKGROUND=40

declare -i _colnum=0
for _color in BLACK RED GREEN YELLOW BLUE MAGENTA CYAN WHITE ; do
    _fg_varname="COLOR_${_color}"
    _fg=$(( $OFFSET_FOREGROUND + $_colnum ))

    _bg_varname="COLOR_ON_${_color}"
    _bg=$(( $OFFSET_BACKGROUND + $_colnum ))


    ## @@ HACK: I hate this shit. bash has indirect expansion, but not
    ## indirect assignment? Unless I'm missing something...

    eval "$(printf "declare -ri COLOR_%s=%d    " "${_color}" ${_fg} )"
    eval "$(printf "declare -ri COLOR_ON_%s=%d " "${_color}" ${_bg} )"

    _colnum+=1
done


## Be nice to the environment and clean up our temporary variables. We
## needed these, because we couldn't have wrapped the whole thing in a
## function and still used 'declare -ri' in our 'eval' calls, since
## that would have declared function-local variables, not globals.

unset _colnum
unset _color
unset _fg_varname
unset _fg
unset _bg_varname
unset _bg


color () {
    ## Return a string with the concatenated ANSI escape sequences for
    ## each of the colors and attributes specified in the args.

    ## Use within a $(...) command substitution block. E.g.,
    ##
    ## printf "my %sred%s text" "$(color red)" "$(color reset)"

    ## ------------------------------------------------------------------
    ## @@ NOTE: Color and attribute names are not case-sensitive.
    ## ------------------------------------------------------------------
    ## @@ NOTE: Specify a background color by prefixing the color name
    ## with "on_". E.g., "$(color bold white on_red)" specifies bold
    ## white text on a red background.
    ## ------------------------------------------------------------------

    for _arg in "${@}" ; do
        local color_name="$(printf "%s" "${_arg}" | tr '[:lower:]' '[:upper:]')" ; shift
        local color_varname="COLOR_${color_name}"

        printf "\e[%dm" ${!color_varname}
    done
}

## end ANSI helpers
## ----------------------------------------------------------------------




## ----------------------------------------------------------------------
## enscript language highlighting usage helpers
## ----------------------------------------------------------------------

awkscr_list_langs () {
    ## returns the awk script to parse the list of languages known to
    ## enscript / states for highlighting

    ## @@ HACK: I hate inlining scripts in other languages.

    ## ANSI escape sequences for colors
    local color_default="$(color default)"
    local color_lang="$(color bold white)"
    local color_desc="$(color cyan)"

    cat - <<EOF_AWK_LIST_LANGS

## List available highlight languages in 'lang: description' form

/^Name:/        {
  printf "\n%s%s:%s",
    "${color_lang}",
    \$2,
    "${color_default}"
    ;
}

/^Description:/ {
  ## @@ HACK: I can't seem to get variable assignment to work (I
  ## know!) so I'm just punting and inlining the expressions.

  printf "%s%s%s",
    "${color_desc}",
    substr( \$0,
        length( "Description: " ),
        length( \$0 ) - length( "Description: " ) ),
    "${color_default}"
    ;
}

END {
  print
}

EOF_AWK_LIST_LANGS
}

## end enscript highlighting usage
## ----------------------------------------------------------------------




prettify () {
    local src_lang="${1}" ; shift
    local filter="${SYNSCRIPT_BIN:-${DEFAULT_SYNSCRIPT_BIN}} -t ${SYNSCRIPT_THEME:-${DEFAULT_SYNSCRIPT_THEME}} -s ${SYNSCRIPT_SYNTAX_DIR:-${DEFAULT_SYNSCRIPT_SYNTAX_DIR}} %s"

    # ${src_lang:+--highlight="${src_lang}"}			\

    enscript \
        --output=-						\
        \
        --escapes \
        --filter="${filter}" \
	      --color=${USE_COLOR:-${DEFAULT_USE_COLOR}}		\
	      --fancy-header="${HEADER:-${DEFAULT_HEADER}}"		\
	      --font="${FONT:-${DEFAULT_FONT}}"			\
	      --language="${OUTPUT_FORMAT:-${DEFAULT_OUTPUT_FORMAT}}"	\
        ${LINE_NUMBERS:+--line-numbers} \
	      --margins=${left}:${right}:${top}:${bottom}		\
	      --mark-wrapped-lines=arrow				\
	      --media="${PAPERSIZE:-${DEFAULT_PAPERSIZE}}"						\
	      --${ORIENTATION:-${DEFAULT_ORIENTATION}}						\
	      --style="${COLORSCHEME:-${DEFAULT_COLORSCHEME}}"	\
        --tabsize="${TABSIZE:-${DEFAULT_TABSIZE}}" \
	      --word-wrap						\
        ${DEBUG:+--verbose} \
	      "${@}"
}




## ----------------------------------------------------------------------
## Command-line options and config processing
## ----------------------------------------------------------------------

## ----------------------------------------------------------------------
## @@ TODO: support reading from stdin
## ----------------------------------------------------------------------
## @@ TODO: wrap this in a function (?)
## ----------------------------------------------------------------------

merge=0
open_pdfs=0
outfile=""
while getopts "hl:mo" opt ; do
    case "${opt}" in
        h)
            usage
            exit
            ;;


        l)
            ## @@ HACK: note ${PAGER:--R} hack, to pass '-R' to less
            src_lang="${OPTARG}"
            if [[ "${src_lang}" == "?" ]] ; then
                enscript --help-highlight \
                    | awk "$(awkscr_list_langs)" \
                    | ${PAGER:-less -R} \
                    ;
                exit
            fi
            ;;


        m)
            ## @@ TODO: -m filename.pdf' to override default merged filename
            merge=1
            outfile="${MERGED_OUTPUT_FILENAME}"
            ;;

        o)
            open_pdfs=1
            ;;
    esac
done
shift $(( ${OPTIND} - 1 ))
OPTIND=1

## end command-line processing
## ----------------------------------------------------------------------




## ----------------------------------------------------------------------
## Program main entry point (i.e., the actual purpose...)
## ----------------------------------------------------------------------

_pp () {
    if (( ${merge} )) ; then
        printf "merging"
        printf " %s" "${@}"
        printf ": "

        prettify "${src_lang}" "${@}"	\
	          | ps2pdf - -		\
	                   > "${outfile}"

        if (( ${open_pdfs} )) ; then
            open "${outfile}"
        fi
    else
        for srcfile in "$@" ; do
	          printf "%s : " "${srcfile}"
	          prettify "${src_lang}" "${srcfile}" \
	              | ps2pdf - -			\
                         > "${srcfile}.pdf"
            if (( ${open_pdfs} )) ; then
                open "${srcfile}.pdf"
            fi
        done
    fi
}

_pp "${@}"
