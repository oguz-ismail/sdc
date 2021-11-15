# Copyright 2021 Oguz Ismail Uysal
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

export LC_ALL=POSIX
export POSIXLY_CORRECT=
unset BC_ENV_ARGS
unset BC_LINE_LENGTH

r1=0 r2=0 r3=0 r4=0
r5=0 r6=0 r7=0 r8=0

fatal() {
	printf '%s: ' "$0"
	case $1 in
	(1)
		printf 'invalid token' ;;
	(2)
		printf 'operator unexpected'
	esac
	printf ': %s (#%d)\n' "$token" $addr
	exit $1
} >&2

nonfatal() {
	case $status in
	(4)
		status=5 ;;
	(5)
		;;
	(*)
		status=4
	esac
	printf '%s: %s (#%d): ' "$0" "$token" $addr
	case $1 in
	(1)
		printf 'fewer elements on the stack than required' ;;
	(2)
		printf 'fewer elements on the region than specified' ;;
	(3)
		printf 'TODO' ;;
	(4)
		printf 'TODO'
	esac
	printf '\n'
} >&2

parseopt()
	case $1 in
	(-[hms])
		call=${1#-} ;;
	(-H)
		format=1 ;;
	(-M)
		call=m format=2 ;;
	(-v)
		call=d format=3 ;;
	(-t)
		call=d format=4 ;;
	(*)	
		return 1
	esac

popmark() {
	case $marks in
	(0)
		return 1
	esac
	marks=${marks#* }
	pmark=$mark
	mark=${marks%% *}
}

pushmark() {
	marks="$1 $marks" mark=$1
}

resetmark() {
	plist=
	until test $mark -le $1; do
		popmark
		plist="$plist$pmark "
	done
}

evaldsgnr() {
	case $token in
	(d*)
		dvalue=86400 ;;
	(h*|:*:*)
		dvalue=3600 ;;
	(m*|:*)
		dvalue=60 ;;
	(s|'')
		return 1
	esac
	token=${token#?}
}

evalfield() {
	fvalue=${token%%[!.0-9]*}
	token=${token#$fvalue}
	if evaldsgnr; then
		fvalue="($fvalue * $dvalue)"
		test $token
	else
		return
	fi
}

case $SDC_INTL_SCALE in
(''|*[!0-9]*)
	SDC_INTL_SCALE=20
esac

call=h format=0
if parseopt "$1"; then
	shift
fi

status=0

addr=-2
smark=0
arity=0

for token in . k0 "$@"; do
	addr=$((addr + 1))

	# meta-commands
	case $token in
	(i)
		token=
		if test -t 0; then
			printf '> ' >/dev/tty
		fi
		read -r token
	esac

	value=
	case $token in
	# commands for controlling regions
	(,)
		pushmark $#
		continue ;;
	(.)
		marks=0 mark=0
		continue ;;
	(j|J)
		if popmark; then
			case $token in
			(J)
				smark=$pmark
			esac
		else
			nonfatal 3
		fi
		continue ;;
	(s)
		if test $smark -ge $#; then
			pushmark $#
		elif test $smark -ge $mark; then
			pushmark $smark
		else
			nonfatal 4
		fi
		continue ;;
	([QWqw]?*)
		if ! popmark; then
			nonfatal 3
			continue
		fi
		case $token in
		(Q0|W0|?0?*|?*[!0-9]*)
			fatal 1
		esac
		count=${token#?}
		case $token in
		(q*)
			origin=$# ;;
		([QW]*)
			origin=$pmark ;;
		(w*)
			origin=$mark
		esac
		case $token in
		([Qq]*)
			if test $count -ge $origin; then
				umark=0
			else
				umark=$((origin - count))
			fi
			resetmark $umark ;;
		([Ww]*)
			umark=$((origin + count))
			if test $umark -gt $#; then
				umark=$#
			fi
		esac
		pushmark $umark
		continue ;;
	# commands for controlling the stack
	(n)
		value=$arity ;;
	(d*)
		if test $# -lt 1; then
			nonfatal 1
			continue
		fi
		case $token in
		(?)
			count=1 ;;
		(?0*|?*[!0-9]*)
			fatal 1 ;;
		(*)
			count=${token#?}
		esac
		bound=$(($# + count))
		while test $# -lt $bound; do
			set -- "$1" "$@"
		done
		continue ;;
	(f*|F|u)
		case $token in
		(F)
			bound=$mark ;;
		(u)
			if popmark; then
				bound=$mark
				pushmark $((bound + ($# - pmark)))
			else
				nonfatal 3
				continue
			fi ;;
		(*)
			case $token in
			(?)
				count=2 ;;
			(?0*|?*[!0-9])
				fatal 1 ;;
			(*)
				count=${token#?}
			esac
			if test $# -lt $count; then
				nonfatal 1
				continue
			fi
			bound=$(($# - count))
			resetmark $bound
			for pmark in $plist; do
				pushmark $((bound + ($# - pmark)))
			done
		esac
		rlist=
		while test $# -gt $bound; do
			rlist="'$1' $rlist"
			shift
		done
		eval "set -- $rlist \"\$@\""
		continue ;;
	(p*)
		case $token in
		(p)
			count=1 ;;
		(p0*|p*[!0-9]*)
			fatal 1 ;;
		(*)
			count=${token#?}
		esac
		if test $# -ge $count; then
			shift $count
			resetmark $#
		else
			nonfatal 1
		fi
		continue ;;
	(k?*)
		case $token in
		(?0?*|?*[!0-9]*)
			fatal 1
		esac
		bound=$((mark + ${token#?}))
		if test $# -lt $bound; then
			nonfatal 2
		else
			shift $(($# - bound))
		fi
		continue ;;
	# commands for controlling registers
	(l[1-8])
		eval value=\$r${token#?} ;;
	([cm][1-8]|[cm][1-8]-|[cm][1-8]-[1-8])
		case $token in
		(*-)
			bound=${token#?}
			bound=${bound%-}
			count=$(($# - mark))
			if test $count -lt 1; then
				nonfatal 2
				continue
			fi
			index=$((bound + count - 1))
			if test $index -gt 8; then
				index=8
				count=$((index - bound + 1))
			fi ;;
		(*)
			case $token in
			(??)
				bound=${token#?}
				index=$bound ;;
			(*)
				bound=${token#?}
				index=${bound#*-}
				bound=${bound%-*}
				if test $index -lt $bound; then
					fatal 1
				fi
			esac
			count=$((index - bound + 1))
			if test $# -lt $count; then
				nonfatal 1
				continue
			fi
		esac
		for value; do
			eval r$index=\$value
			if test $((index -= 1)) -lt $bound; then
				break
			fi
		done
		case $token in
		(m*)
			shift $count
			resetmark $#
		esac
		continue ;;
	# quasi-binary operators
	([r]*)
		if test $# -lt 1; then
			fatal 2
		fi
		case $token in
		(r|rs)
			token=r value=0 ;;
		(r[dhm])
			token=${token#?}
			evaldsgnr
			token=k value=$dvalue ;;
		(?*[!0-9]*|r*[!0]?*)
			fatal 1 ;;
		(*)
			value=${token#?}
			token=${token%$value}
		esac
		arity=1
		value="$token($1, $value)"
		shift ;;
	# binary operators
	(+|-|x|/|%|//)
		if test $# -lt 2; then
			fatal 2
		fi
		arity=2
		case $token in
		(/)
			token=f ;;
		(//)
			token=/
		esac
		case $token in
		([a-z])
			value="$token($2, $1)" ;;
		(*)
			value="($2 $token $1)"
		esac
		shift 2
		resetmark $# ;;
	# n-ary operators
	(*[agl])
		case $token in
		(?)
			arity=$(($# - mark))
			bound=$mark
			if test $arity -lt 1; then
				fatal 2
			fi ;;
		(0*|*[!0-9]*?)
			fatal 1 ;;
		(*)
			arity=${token%?}
			if test $# -lt $arity; then
				fatal 2
			fi
			token=${token#$arity}
			bound=$(($# - arity))
		esac
		value=$1
		shift
		while test $# -gt $bound; do
			value="$token($value, $1)"
			shift
		done
		resetmark $# ;;
	# gibberish
	(*[!.0-9:dhms-]*|[!0-9-]*|?*-*|*s?*|*[.:]|*[dhms]*[!dhms]|*[!0-9][!0-9]*|*.*[.:dhm]*|*:*:*:*|*d*d*|*h*[dh]*|*m*[dhm]*|*:*[dhms]*|*[dhms]*:*|*.?????????[0-9]*)
		fatal 1 ;;
	# time strings
	('')
		value=0 ;;
	(*)
		sign=
		case $token in
		(-*)
			sign=- token=${token#?}
		esac
		if
			while evalfield; do
				! value="$value$fvalue + "
			done
		then
			value="$sign$fvalue"
		else
			value="$sign($value$fvalue)"
		fi
	esac
	set -- "$value" "$@"
done

# TAG: POSIX.1-202x
# set -o pipefail

case $call in
(d)
	bc | paste -d '\0' - - - - - ;;
(h)
	bc | paste -d '\0' - - - ;;
(m)
	bc | paste -d '\0' - - ;;
(s)
	bc
esac << eof
define x(x, y) {
	scale = $SDC_INTL_SCALE
	x *= y
	scale = 0
	return(x)
}

define f(x, y) {
	scale = $SDC_INTL_SCALE
	x /= y
	scale = 0
	return(x)
}

define a(x, y) {
	return(x + y)
}

define g(x, y) {
	if (x > y) {
		return(x)
	}
	return(y)
}

define l(x, y) {
	if (x < y) {
		return(x)
	}
	return(y)
}

define k(x, n) {
	auto s
	s = 1
	if (x < 0) {
		s = -s
		x = -x
	}
	if (x % (n * 2) != n / 2) {
		x += n / 2
	}
	x = s * x / n * n
	return(x)
}

define r(x, n) {
	auto s
	if (n < scale(x)) {
		s = 1
		if (x < 0) {
			s = -s
			x = -x
		}
		if (x * 10^(n + 1) % 20 != 5) {
			scale = n + 1
			x += .5 * 10^-n
		}
		scale = n
		x = s * x / 1
		scale = 0
	}
	return(x)
}

define t(x) {
	while (scale < scale(x)) {
		if (x / 1 == x) {
			break
		}
		scale += 1
	}
	x /= 1
	scale = 0
	return(x)
}

f = $format

define p(x) {
	if (f >= 3) {
		x = r(x, 0)
	}
	x = r(t(x), 9)
	if (x < 0) {
		"-"
		x = -x
	}
	return($call(x, 0))
}

define d(t, s) {
	if (t >= 86400) {
		t / 86400
		if (f == 3) {
			" days"
		}
		if (f == 4) {
			"d"
		}
		return(h(t % 86400, 1))
	}
	"
"
	return(h(t, s))
}

define h(t, s) {
	if (t >= 3600) {
		if (f == 3) {
		if (s == 1) {
			", "
		}
		}
		t / 3600
		if (f == 3) {
			" hours"
		}
		if (f == 4) {
			"h"
		}
		return(m(t % 3600, 1))
	}
	if (f == 1) {
		0
		return(m(t, 1))
	}
	"
"
	return(m(t, s))
}

define m(t, s) {
	if (f <= 1) {
	if (s == 1) {
		":"
	}
	}
	if (t >= 60) {
		if (s == 1) {
			if (f <= 1) {
			if (t < 600) {
				"0"
			}
			}
			if (f == 3) {
				", "
			}
		}
		t / 60
		if (f == 3) {
			" minutes"
		}
		if (f == 4) {
			"m"
		}
		return(s(t % 60, 1))
	}
	if (f <= 1) {
	if (s == 1) {
		"00"
	}
	}
	if (f == 2) {
		0
		return(s(t, 1))
	}
	"
"
	return(s(t, s))
}

define s(t, s) {
	auto n
	if (f <= 2) {
		if (s == 1) {
			":"
			if (t < 10) {
				"0"
			}
		}
		/* Not all bc implementations
		 * print the leading zero. */
		if (t > 0) {
		if (t < 1) {
			"0."
			for (n = 0; t < .1; n++) {
				"0"
				t *= 10
			}
			t * 10^(scale(t) - n) / 1
			return
		}
		}
		t
		return
	}
	if (s == 1) {
		if (t == 0) {
			"
"
		}
		if (t >= 1) {
			if (f == 3) {
				", "
			}
			s = 0
		}
	}
	if (s == 0) {
		t
		if (f == 3) {
			" seconds"
		}
		if (f == 4) {
			"s"
		}
	}
	"
"
}
$(
if test $# -ge 1; then
	printf '\nu = p(%s)' "$@"
fi
)
eof

if test $? -ne 0; then
	status=3
fi

exit $status

# vim: ft=sh
