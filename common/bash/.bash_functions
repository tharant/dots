#!/bin/bash

pwg() {
	# Portable 32-char alphanumeric password (was macOS-only sf-pwgen)
	LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32
	echo
}

# Copy stdin to the system clipboard (macOS pbcopy, clip.exe under WSL,
# wl-copy/xclip elsewhere); warns and fails if no clipboard tool exists.
clip-copy() {
	if command -v pbcopy &>/dev/null; then
		pbcopy
	elif grep -qi microsoft /proc/version 2>/dev/null; then
		if [[ -x /mnt/c/Windows/System32/clip.exe ]]; then
			/mnt/c/Windows/System32/clip.exe
		else
			echo "clip-copy: /mnt/c/Windows/System32/clip.exe not found" 1>&2
			return 1
		fi
	elif command -v wl-copy &>/dev/null; then
		wl-copy
	elif command -v xclip &>/dev/null; then
		xclip -selection clipboard -in
	else
		echo "clip-copy: no clipboard tool found (pbcopy, clip.exe, wl-copy, xclip)" 1>&2
		return 1
	fi
}

# Open a URL/file with the first available opener
open-url() {
	if command -v open &>/dev/null; then
		open "$1"
	elif command -v wslview &>/dev/null; then
		wslview "$1"
	elif command -v xdg-open &>/dev/null; then
		xdg-open "$1"
	else
		echo "open-url: no opener found (open, wslview, xdg-open)" 1>&2
		return 1
	fi
}

# simple command line calculator
calc() {
	awk "BEGIN{ print $* }" ;
}

query_store() {
  local query="${1}"
  echo "${query}" | psql --username postgres --host aerosmith.imirus.com -p 5432 --dbname imirusMain -tA
}

query_vm() {
  local database="${1}"
  local query="${2}"
  echo "${query}" | psql --username postgres --host bs.imirus.com -p 5432 --dbname "${database}_db" -tA
}

query_vm_as_csv() {
  local database="${1}"
  local query="${2}"
  echo "${query}" | psql --host bs.imirus.com --username postgres --dbname "${database}_db" -F\",\" -A \
    | sed -e 's/^/"/g' -e 's/$/"/g' \
    | grep -Ev '^"\('
}

query_store_as_csv() {
  echo "${1}" \
    | psql --username postgres --host as.imirus.com -p 5432 --dbname imirusMain -F\",\" -A \
    | sed -e 's/^/"/g' -e 's/$/"/g' \
    | grep -Ev '^"\('
}

publist() {
	local sql="SELECT vm_name FROM v_publisher WHERE enable_vm = 't';"
  query_store "${sql}" | sort -u
}

pubinfo() {
	local data="${1}"
	local isql="SELECT vm_name FROM v_publisher WHERE id = ${data};"
	local nsql="SELECT id FROM v_publisher WHERE vm_name = '${data}';"
	if [[ ${data} -gt 0 ]]; then
		query_store "${isql}"
	else
		query_store "${nsql}"
	fi
}

titleinfo() {
	local t_id="${1}"
	local qsql="
    SELECT v_title_list.label, v_publisher.vm_name, v_title_list.pub_id
    FROM v_title_list
    JOIN v_publisher ON v_title_list.pub_id = v_publisher.id
    WHERE v_title_list.id = ${t_id};"
	local data
	data=$(query_store "${qsql}")
	local name
	name=$(echo "${data}" | cut -d "|" -f1)
	local p_nm
	p_nm=$(echo "${data}" | cut -d "|" -f2)
	local p_id
	p_id=$(echo "${data}" | cut -d "|" -f3)
	cat <<-EOF

  name:       ${name}
  pub_name:   ${p_nm}
  pub_id:     ${p_id}
  path:       /srv/www/imirus2/${p_id}/${t_id}

EOF
}

maginfo() {
   local m_id="${1}"
   local qsql="
     SELECT volume, issue, v_publisher.vm_name, issue_name, pub_id, title_id
     FROM i_magazine
     JOIN v_publisher on i_magazine.pub_id = v_publisher.id
     WHERE i_magazine.id = ${m_id};"
   local data
   data=$(query_store "${qsql}")
   local volm
   volm=$(echo "${data}" | cut -d "|" -f1)
   local issu
   issu=$(echo "${data}" | cut -d "|" -f2)
   local p_nm
   p_nm=$(echo "${data}" | cut -d "|" -f3)
   local name
   name=$(echo "${data}" | cut -d "|" -f4)
   local p_id
   p_id=$(echo "${data}" | cut -d "|" -f5)
   local t_id
   t_id=$(echo "${data}" | cut -d "|" -f6)
   local wurl="https://view.imirus.com/${t_id}/document/${m_id}/page/0"

   cat <<EOF

   name:       ${name}
   pub_id:     ${p_id}
   vm_name:    ${p_nm}
   title_id:   ${t_id}
   path:       /srv/www/imirus2/${p_id}/${t_id}/v${volm}i${issu}/
   url:        ${wurl}

EOF
}

prodinfo() {
   local prod="${1}"
   local qsql="
      SELECT volume, issue, vm_name, v_title_list.label, issue_name, i_magazine.pub_id, i_magazine.title_id, i_magazine.id
      FROM i_magazine
      JOIN v_publisher ON i_magazine.pub_id = v_publisher.id
      JOIN v_title_list ON i_magazine.title_id = v_title_list.id
      WHERE i_magazine.id = (
        SELECT mag_id
        FROM r_product_magazine
        WHERE prod_id = ${prod}
      );"
	 local data
	 data=$(query_store "${qsql}")
   local volm
   volm=$(echo "${data}" | cut -d "|" -f1)
   local issu
   issu=$(echo "${data}" | cut -d "|" -f2)
   local vm_name
   vm_name=$(echo "${data}" | cut -d "|" -f3)
   local t_nm
   t_nm=$(echo "${data}" | cut -d "|" -f4)
   local name
   name=$(echo "${data}" | cut -d "|" -f5)
   local p_id
   p_id=$(echo "${data}" | cut -d "|" -f6)
   local t_id
   t_id=$(echo "${data}" | cut -d "|" -f7)
	 local m_id
	 m_id=$(echo "${data}" | cut -d "|" -f8)
   local wurl="https://view.imirus.com/${t_id}/document/${m_id}/page/0"
   cat <<EOF

   name:      ${name}
   pub_id:    ${p_id}
   vm_name:   ${vm_name}
   title_id:  ${t_nm}, ${t_id}
   mag_id:    ${m_id}
   path:      /srv/www/imirus2/${p_id}/${t_id}/v${volm}i${issu}/
   url:       ${wurl}

EOF
}

scroller() {
	while true; do banner "${1}" | while IFS=$'\n' read -r l; do echo "$l";
	sleep 0.01;
	done;
	done
}

# average a column of numbers
# must specify the column number
# example `cat file |avg 2`
avg() {
	awk "/$2/{sum += \$$1; lc += 1;} END {printf \"Average over %d lines: %f\n\", lc, sum/lc}";
}

sum() {
	awk "/$2/{sum += \$$1; lc += 1;} END {printf \"Sum of %d lines: %f\n\", lc, sum}";
}

num2ip() {
	local w=$(( ${1} / 16777216 % 256 ))
	local x=$(( ${1} / 65536 % 256 ))
	local y=$(( ${1} / 256 % 256 ))
	local z=$(( ${1} % 256 ))
 	echo "${w}.${x}.${y}.${z}"
}

ip2num() {
	local w=$(( $(echo "${1}" | cut -d "." -f1) * 16777216 ))
	local x=$(( $(echo "${1}" | cut -d "." -f2) * 65536 ))
	local y=$(( $(echo "${1}" | cut -d "." -f3) * 256 ))
	local z
	z=$(echo "${1}" | cut -d "." -f4)
	echo $(( w + x + y + z ))
}

now() {
  /bin/date "+%s000"
}

get_magazine_path() {
  maginfo "${1}" | grep path | awk '{print $2}'
}

magazine-dir() {
  local path
  path=$(get_magazine_path "$1")
  if [ $# -gt 1 ]; then
    case $2 in
      "cd")
        cd "${path}" || return
        ;;
      *)
        echo "${path}"
        ;;
    esac
  else
    echo "${path}"
  fi
}

get_title_path() {
  titleinfo "${1}" | grep path | awk '{print $2}'
}

title-dir() {
  local path
  path=$(get_title_path "$1")

  if [ $# -gt 1 ]; then
    case $2 in
      "cd")
        cd "${path}" || return
        ;;
      *)
        echo "${path}"
        ;;
    esac
  else
    echo "${path}"
  fi
}

open-magazine() {
   local url
   url=$(maginfo "$1" | grep "url:" | awk '{print $2}')
   open-url "$url"
}

diskspeedtest() {
  local st
  st=$(now)
  # gdd (coreutils) on macOS, plain dd everywhere else
  local dd_bin
  dd_bin="$(command -v gdd 2>/dev/null || command -v dd 2>/dev/null)"
  local wr
  wr=$("${dd_bin}" if=/dev/zero of=file bs=4k count=1024k conv=fdatasync 2>&1 | grep copied | cut -d " " -f10-)
  local rd
  rd=$("${dd_bin}" if=file of=/dev/null bs=4k count=1024k conv=fdatasync 2>&1 | grep copied | cut -d " " -f10-)
  rm -f file
  local ed
  ed=$(now)
  local du
  du=$(calc "$(calc "$ed" - "$st")" / 1000)
  echo -en "write: $wr, read: $rd - test took $du seconds to complete.\n"
}

fix_header() {
  local out
  out=$1
  # get the header, convert space and fwd slash to underscore, then convert to lowercase
  head -n1 "${out}" \
    | sed -e 's/ /_/g' -e 's#/#_#g' -e 's/-/_/g' -e 's/?//g' -e 's/\$//g' -e 's/</_less_than_/g' -e 's/>/_greater_than_/g' \
    | tr '[:upper:]' '[:lower:]' \
    | tr -s "_" "_"
  sed 1d "${out}"
}


aws-use-tdn() {
  export AWS_PROFILE=tdn
}

aws-use-imirus() {
  export AWS_PROFILE=imirus
}

aws-use-wasabi-imirus() {
  export AWS_PROFILE=wasabi-imirus
}

aws-use-boodle() {
  export AWS_PROFILE=boodle
}

aws-use-boodle-root() {
  export AWS_PROFILE=boodle-root
}

use-kubeconfig () {
  if [[ $# -ne 1 ]]; then
    if [[ -z ${USING_KUBECONFIG} ]]; then
      echo "No context specified; available contexts are:" 1>&2;
      kubectl config view -o json | jq -r '.contexts[].name' 1>&2;
    else
      kubectl config use-context "${USING_KUBECONFIG}"
    fi
  else
    if [[ ${#1} -eq 4 ]]; then
      export USING_KUBECONFIG="aws-kube-${1}.boodle.ai";
      kubectl config use-context "aws-kube-${1}.boodle.ai";
    else
      export USING_KUBECONFIG="${1}";
      kubectl config use-context "${1}";
    fi;
  fi
}



mycli () {
  # type -P skips this function and finds the real binary
  local mycli_bin
  mycli_bin="$(type -P mycli)" || { echo "mycli: not installed" 1>&2; return 1; }
  if [[ $# -eq 0 ]]; then
    "${mycli_bin}";
  else
    "${mycli_bin}" --defaults-group-suffix "$1";
  fi
}

shortsha() {
  local sha
  sha="$(git rev-parse --short=8 HEAD)" || return 1
  printf '%s\n' "${sha}" | clip-copy
  echo "${sha}"
}
