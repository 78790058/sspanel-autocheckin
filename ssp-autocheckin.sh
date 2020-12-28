#!/bin/bash

PATH="/usr/local/bin:/usr/bin:/bin"

ENV_PATH="$(dirname $0)/.env"

IS_MACOS=$(uname | grep 'Darwin' | wc -l)

TITLE="SSPanel Auto Checkin 签到结果"

if [ -f ${ENV_PATH} ]; then
    source ${ENV_PATH}
fi

if [ "${DOMAIN}" == "" ] || [ "${USERNAME}" == "" ] || [ "${PASSWD}" == "" ]; then
    echo "环境常量未配置，请正确配置 DOMAIN、USERNAME 和 PASSWD 值" && exit 1
fi

if [ $(command -v jq) == "" ]; then
    echo "依赖缺失: jq，查看 https://github.com/isecret/sspanel-autocheckin/blob/master/README.md 安装" && exit 1
fi

COOKIE_PATH="./.ss-autocheckin.cook"

PUSH_TMP_PATH="./.ss-autocheckin.tmp"

login=$(curl "${DOMAIN}/auth/login" -d "email=${USERNAME}&passwd=${PASSWD}&code=" -c ${COOKIE_PATH} -L -k -s)

start_time=$(date '+%Y-%m-%d %H:%M:%S')
login_code=$(echo ${login} | jq -r '.ret')
login_status=$(echo ${login} | jq -r '.msg')

login_log_text="【签到站点】: ${DOMAIN}\n\n"
login_log_text="${login_log_text}【签到用户】: ${USERNAME}\n\n"
login_log_text="${login_log_text}【签到时间】: ${start_time}\n\n"

if [ ${login_code} -eq 0 ]; then
    login_log_text="${login_log_text}【签到状态】: 登录失败, 请检查配置\n\n"
    echo -e ${login_log_text}

    if [ "${PUSH_KEY}" ]; then
        echo -e "text=${TITLE}&desp=${login_log_text}" > ${PUSH_TMP_PATH}
        push=$(curl -k -s --data-binary @${PUSH_TMP_PATH} "https://sc.ftqq.com/${PUSH_KEY}.send")
        push_code=$(echo ${push} | jq -r ".errno")
        if [ ${push_code} -eq 0 ]; then
            echo -e "【推送结果】: 成功\n"
        else
            echo -e "【推送结果】: 失败\n"
        fi
    fi
    exit 1;
fi

userinfo=$(curl -k -s -G -b ${COOKIE_PATH} "${DOMAIN}/getuserinfo")
user=$(echo ${userinfo} | tr '\r\n' ' ' | jq -r ".info.user")

# 等级过期时间
class_expire=$(echo ${user} | jq -r ".class_expire")
# 账户过期时间
expire_in=$(echo ${user} | jq -r ".expire_in")
# 上次签到时间
last_check_in_time=$(echo ${user} | jq -r ".last_check_in_time")
# 用户余额
money=$(echo ${user} | jq -r ".money")
# 用户限速
node_speedlimit=$(echo ${user} | jq -r ".node_speedlimit")
# 总流量
transfer_enable=$(echo ${user} | jq -r ".transfer_enable")
# 总共使用流量
last_day_t=$(echo ${user} | jq -r ".last_day_t")
# 剩余流量
transfer_used=$(expr ${transfer_enable} - ${last_day_t})
# 转换 GB
transfer_enable_text=$(echo ${transfer_enable} | awk '{ byte =$1 /1024/1024**2 ; print byte " GB" }')
last_day_t_text=$(echo ${last_day_t} | awk '{ byte =$1 /1024/1024**2 ; print byte " GB" }')
transfer_used_text=$(echo ${transfer_used} | awk '{ byte =$1 /1024/1024**2 ; print byte " GB" }')
# 转换上次签到时间
if [ ${IS_MACOS} -eq 0 ]; then 
    last_check_in_time_text=$(date -d "1970-01-01 UTC ${last_check_in_time} seconds" "+%F %T")
else
    last_check_in_time_text=$(date -r ${last_check_in_time} '+%Y-%m-%d %H:%M:%S')
fi

user_log_text="【用户余额】: ${money} CNY\n\n"
user_log_text="${user_log_text}【用户限速】: ${node_speedlimit} Mbps\n\n"
user_log_text="${user_log_text}【总流量】: ${transfer_enable_text}\n\n"
user_log_text="${user_log_text}【剩余流量】: ${transfer_used_text}\n\n"
user_log_text="${user_log_text}【已使用流量】: ${last_day_t_text}\n\n"
user_log_text="${user_log_text}【等级过期时间】: ${class_expire}\n\n"
user_log_text="${user_log_text}【账户过期时间】: ${expire_in}\n\n"
user_log_text="${user_log_text}【上次签到时间】: ${last_check_in_time_text}\n\n"

checkin=$(curl -k -s -d "" -b ${COOKIE_PATH} "${DOMAIN}/user/checkin")
chechin_code=$(echo ${checkin} | jq -r ".ret")
checkin_status=$(echo ${checkin} | jq -r ".msg")

if [ "${checkin_status}" ]; then
    checkin_log_text="【签到状态】: ${checkin_status}\n\n"
else
    checkin_log_text="【签到状态】: 签到失败, 请检查是否存在签到验证码\n\n"
fi

result_log_text="${login_log_text}${checkin_log_text}${user_log_text}"

echo -e ${result_log_text}

if [ "${PUSH_KEY}" ]; then
    echo -e "text=${TITLE}&desp=${result_log_text}" > ${PUSH_TMP_PATH}
    push=$(curl -k -s --data-binary @${PUSH_TMP_PATH} "https://sc.ftqq.com/${PUSH_KEY}.send")
    push_code=$(echo ${push} | jq -r ".errno")
    if [ ${push_code} -eq 0 ]; then
        echo -e "【推送结果】: 成功\n"
    else
        echo -e "【推送结果】: 失败\n"
    fi
fi

rm -rf ${COOKIE_PATH}
rm -rf ${PUSH_TMP_PATH}
