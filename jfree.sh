#!/bin/bash

jps_cache_file=/tmp/.jps
#jps_cache_file=$(dirname $(readlink -f $0))/.jps

# 变量声明
keys=(stat s0c s1c s0u s1u ec eu oc ou mc mu ccsc ccsu ygc ygct fgc fgct gct)

# 计算表达式，并对结果进行四舍五入
# @param $1 计算表达式
# @param $2 保留小数位数，默认 2 位
# @example round "(1+2)/10"
function round() {
  df=${2:-2}
  printf '%.*f\n' "$df" "$(bc -l <<< "a=$1; if(a>0) a+=5/10^($df+1) else if (a<0) a-=5/10^($df+1); scale=$df; a/1")"
}

# 格式化输出，支持中文不错版
# @param -a 对齐方式，默认 right 右对齐（如果 -l 没有设置，则 align 无效），可取 <left|center|right>
# @param -l 显示长度，内容长度短于该选项会自动填充，大于则会截断
# @param -n 是否换行，默认输出完内容后不换行
# @param -h 打印 usage
# @param $1 需要输出的内容（$1 shift 后）
function fprint() {
  local OPTIND
  # 参数解析
  while getopts ':a:l:nh' options; do
    case $options in
      a) local align=$OPTARG && test "left" = "$align" -o "center" = "$align" || align=right;;
      l) local length=$OPTARG && [[ "$length" =~ ^[0-9]+$ ]] || length="";;
      n) local newline=$OPTARG && test -n $newline && newline=true;;
      h) printf 'Usage: fprint [-a align(left|center|right)] [-l length] [-n](\\n) [-h](help) contents\n' && exit 0;;
    esac
  done && shift $(($OPTIND-1))
  # 简单打印
  test -z "$1" -o -z "$length" && {
    test "true" = "$newline" && printf "%s\n" $1 || printf "%s" $1
  } && return
  # 中文错版修正
  byte=$(($(echo "$1" | wc -c)-1))    # 字节数，一个中文 3 个字节
  char=${#1}                          # 字符数，一个中文 1 个字符
  byte3=$((($byte-$char)/2))          # 三字节（中文）字符数，一个三字节（中文）字符显示时占用两个光标长度
  byte1=$(($char-$byte3))             # 单字节（英文）字符数，一个单字节（英文）字符显示时占用一个光标长度
  cursor=$(($byte3*2+$byte1))         # 全部展示所需的光标长度
  # 全部展示所需的光标长度 <= 显示长度
  test $cursor -le $length -a "center" = "$align" && {
    fill=$((($length-$cursor)/2))
    content=$(printf "%${fill}s%s" "" "$1")
  } || content="$1"
  offset=$byte3
  # 全部展示所需的光标长度 > 显示长度，需要截取原字符串
  test $cursor -gt $length && {
    offset=0
    # 截取字符串，从最短字符数（展示的全是三字节（中文）字符）开始检测。截取策略为尽可能的使期望占用的光标长度被占满
    i=$(($length/2))
    while test $i -le $char; do
      content="${1:0:$i}"
      content_byte=$(($(echo "$content" | wc -c)-1))
      content_char=${#content}
      content_byte3=$((($content_byte-$content_char)/2))
      content_byte1=$(($content_char-$content_byte3))
      content_cursor=$(($content_byte3*2+$content_byte1))
      if test $content_cursor -gt $length; then
        # 最后一个字符刚好为三字节（中文）字符，并且比 $length 大一个光标位，必须回退一个三字节（中文）字符（$i-1），又小一个光标位，于是补一个空格对齐
        content="${1:0:$(($i-1))} " && break
      elif test $content_cursor -eq $length; then
        break
      fi
      ((i++))
    done
  }
  # 对齐
  test -z "$align" -o "right" = "$align" && length="%$(($length+$offset))s" || length="%-$(($length+$offset))s"
  # 换行
  test "true" = "$newline" && length="$length\n"
  # 重排版打印
  printf "$length" "$content"
}

# 渲染分析结果
function render() { 
  # 终端过窄警告
  test $cols -lt 110 && printf "\033[33m%s\033[0m\n" "[Warning] The terminal is too narrow, and the information will be pruned."
  
  # Overview
  printf "\033[32m"
  fprint -a left -l $half_cols "$(jps -l | grep $1)"
  printf "\033[0m"
  fprint -n -l $half_cols "$(printf "Used: %sM, Capacity: %sM, Usage: %s [Heap]" $used $capacity ${usage}%)"

  # GC
  # border-top
  printf "+%${minor_cols}s+%${major_cols}s+\n" | sed "s/ /-/g"
  # header
  printf "|%${minor_cols}s|%${major_cols}s|\n" \
         "$(fprint -a center -l $minor_cols "Minor GC")" \
         "$(fprint -a center -l $major_cols "Major GC")"
  # body
  printf "|%${minor_cols}s|%${major_cols}s|\n" \
         "$(fprint -a center -l $minor_cols "$ygc times, $ygct seconds")" \
         "$(fprint -a center -l $major_cols "$fgc times, $fgct seconds")"
  
  # Heap
  # border-top
  printf "+%${eden_body_cols}s+%${survivor_body_cols}s+%${survivor_body_cols}s+%${old_body_cols}s+\n" | sed "s/ /-/g"
  # header
  printf "|%${eden_body_cols}s|%${survivor_body_cols}s|%${survivor_body_cols}s|%${old_body_cols}s|\n" \
         "$(fprint -a center -l $eden_body_cols "Eden")" \
         "$(fprint -a center -l $survivor_body_cols "Survivor0")" \
         "$(fprint -a center -l $survivor_body_cols "Survivor1")" \
         "$(fprint -a center -l $old_body_cols "Old")"
  # body
  printf "|%-${eden_body_cols}s|%${survivor_body_cols}s|%${survivor_body_cols}s|%${old_body_cols}s|\n" \
         "$(fprint -a center -l $eden_body_cols "${eu}M / ${ec}M")" \
         "$(fprint -a center -l $survivor_body_cols "${s0u}M / ${s0c}M")" \
         "$(fprint -a center -l $survivor_body_cols "${s1u}M / ${s1c}M")" \
         "$(fprint -a center -l $old_body_cols "${ou}M / ${oc}M")"
  # progress
  printf "|\033[47m%${eden_progress_cols}s\033[0m%${eden_progress_black_cols}s%${progress_cols}s" "" "" ${eden_usage}%
  printf "|\033[47m%${s0_progress_cols}s\033[0m%${s0_progress_black_cols}s%${progress_cols}s" "" "" ${s0_usage}%
  printf "|\033[47m%${s1_progress_cols}s\033[0m%${s1_progress_black_cols}s%${progress_cols}s" "" "" ${s1_usage}%
  printf "|\033[47m%${old_progress_cols}s\033[0m%${old_progress_black_cols}s%${progress_cols}s|\n" "" "" ${old_usage}%
  # border-bottom
  printf "+%${eden_body_cols}s+%${survivor_body_cols}s+%${survivor_body_cols}s+%${old_body_cols}s+\n" | sed "s/ /-/g"
  
  # Metaspace
  # header
  printf "|%${meta_body_cols}s|\n" "$(fprint -a center -l $meta_body_cols "Metaspace")"
  # body
  printf "|%${meta_body_cols}s|\n" "$(fprint -a center -l $meta_body_cols "Used: ${mu}M, Capacity: ${mc}M, Usage: ${meta_usage}%")" 
  # border-bottom
  printf "+%${meta_body_cols}s+\n" | sed "s/ /-/g"
}

# 进度条计算
function progress() {
  progress_cols=7
  # 进度条列数
  eden_progress_cols=$(round "($eden_body_cols-$progress_cols)*$eu/$ec" 0)
  s0_progress_cols=$(round "($survivor_body_cols-$progress_cols)*$s0u/$s0c" 0)
  s1_progress_cols=$(round "($survivor_body_cols-$progress_cols)*$s1u/$s1c" 0)
  old_progress_cols=$(round "($old_body_cols-$progress_cols)*$ou/$oc" 0)
  meta_progress_cols=$(round "($meta_body_cols-$progress_cols)*$mu/$mc" 0)
  # 进度条背板列数
  eden_progress_black_cols=$(($eden_body_cols-$eden_progress_cols-$progress_cols))
  s0_progress_black_cols=$(($survivor_body_cols-$s0_progress_cols-$progress_cols))
  s1_progress_black_cols=$(($survivor_body_cols-$s1_progress_cols-$progress_cols))
  old_progress_black_cols=$(($old_body_cols-$old_progress_cols-$progress_cols))
  meta_progress_black_cols=$(($meta_body_cols-$meta_progress_cols-$progress_cols))
}

# 根据 jstat 输出对 keys 相关变量进行赋值
# @param $1 pid
function stats() {
  stats=$(jstat -gc $1 | sed -n 2p)
  # 批量赋值
  for i in $(seq 0 17); do
    test $i -gt 0 -a $i -lt 13 && {
      tmp=$(echo $stats | awk "{print \$$i}")
      eval ${keys[$i]}=$(round "$tmp/1024")
    } || eval ${keys[$i]}='$(echo $stats | awk "{print \$$i}")'
  done
  # 总计
  used="$(round "$s0u+$s1u+$eu+$ou")"
  capacity="$(round "$s0c+$s1c+$ec+$oc")"
  # 使用率
  meta_usage="$(round "100*$mu/$mc")"
  eden_usage="$(round "100*$eu/$ec")"
  s0_usage="$(round "100*$s0u/$s0c")"
  s1_usage="$(round "100*$s1u/$s1c")"
  old_usage="$(round "100*$ou/$oc")"
  usage="$(round "100*$used/$capacity")"
}

# 查询 java 进程详细内存信息
function show() {
  [[ ! "$1" =~ ^[0-9]+$ ]] && return
  stats $1
  progress
  render $1
}

# 当前选中的 jps 索引
index=0

# jps 列表交互响应
function react() {
  terminal_rows=$(stty size | awk '{print $1}')
  jps_count=$(cat $jps_cache_file | wc -l)
  case $1 in
    up)    test $index -gt 1 && index=$(($index - 1)) || index=$(($jps_count - 1));;
    down)  test $index -lt $(($jps_count - 1)) && index=$(($index + 1)) || index=1;;
    enter) 
      clear && show $(sed -n "$(($index+1))p" $jps_cache_file)
      # 阻塞 show 方法，解除阻塞返回列表
      read -p "Enter any character to return the list: " 
  esac
  line=$(($index + 1))
  # 标题
  clear && sed -n 1p $jps_cache_file
  # 列表
  start_index=2
  test $terminal_rows -gt $jps_count && end_index=$jps_count || {
    end_index=$(($terminal_rows - 1))
    # 是否需要滚动
    scroll=$(($index - $terminal_rows + 2))
    test $scroll -gt 0 && {
      start_index=$(($scroll + 2))
      end_index=$line
    }
  }
  sed -ne $line's/^/\'$'\033[7m&/;'$line's/$/&\'$'\033[27m/;'"${start_index},${end_index}p" $jps_cache_file
}

# jps 列表交互
function interact() {
  while true; do
    read -d '' -sn 1
    test "$REPLY" = $'\e' && {
      read -d '' -sn 1 -t1
      test "$REPLY" = "[" && {
        read -d '' -sn 1 -t1
        case $REPLY in
          A) react up;;
          B) react down;;
        esac
      }
    }
    test "$REPLY" = $'\n' && react enter
  done
}

# jps 缓存
function makecache() {
  printf "%-5s %-s\n" "PID" "JAR" > $jps_cache_file
  jps | grep -v Jps >> $jps_cache_file
  test $(cat $jps_cache_file | wc -l) -gt 1 && return 
  echo "There are no running Java programs." && exit
}

# jps 提供交互式响应
function list_jps_interactive() {
  makecache && clear
  terminal_rows=$(stty size | awk '{print $1}')
  jps_count=$(cat $jps_cache_file | wc -l)
  start_index=1
  test $terminal_rows -gt $jps_count && end_index=$jps_count || end_index=$(($terminal_rows - 1))
  sed -n "$start_index,${end_index}p" $jps_cache_file 
  interact
}

# 网格计算
function columns() {
  # 终端
  cols=$(stty size | awk '{print $2}')
  half_cols=$(($cols/2))
  # 区列数
  survivor_cols=$(round "$cols/6" 0)
  eden_cols=$(($survivor_cols*2))
  old_cols=$(($cols-eden_cols*2))
  # 区列数，去边框
  survivor_body_cols=$(($survivor_cols-1))
  eden_body_cols=$(($eden_cols-1))
  old_body_cols=$(($old_cols-2))
  meta_body_cols=$(($cols-2))
  # 代列数
  minor_cols=$(($survivor_cols*4-1))
  major_cols=$old_body_cols
}

# 依赖检查
function check_dependencies() {
  dependencies=(jps jstat)
  for dependence in ${dependencies[@]}; do
    test ! -x "$(command -v $dependence)" && list+=($dependence)
  done
  test ${#list[@]} -eq 0 && return
  echo "Command not found: ${list[@]}" && exit 1
}

function main() {
  check_dependencies
  columns
  list_jps_interactive
}

main
