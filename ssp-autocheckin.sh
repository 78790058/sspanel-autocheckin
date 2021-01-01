#!/bin/bash

VERSION="2.0.0"

PATH="/usr/local/bin:/usr/bin:/bin"

ENV_PATH="$(dirname $0)/.env"

IS_MACOS=$(uname | grep 'Darwin' | wc -l)

TITLE="SSPanel Auto Checkin v${VERSION} 签到通知"

COOKIE_PATH="./.ss-autocheckin.cook"

if [ -f ${ENV_PATH} ]; then
    source ${ENV_PATH}
fi

if [ -z $(command -v jq) ]; then
    echo "依赖缺失: jq，查看 https://github.com/isecret/sspanel-autocheckin/blob/master/README.md 安装" && exit 1
fi

#检查账户权限
check_root() {
    if [ 0 == $UID ]; then
        echo -e "${Info} 当前用户是 ROOT 用户，可以继续操作" && sleep 1
    else
        echo -e "${Error} 当前非 ROOT 账号(或没有 ROOT 权限)，无法继续操作，请更换 ROOT 账号或使用 su 命令获取临时 ROOT 权限（执行后可能会提示输入当前账号的密码）。" && exit 1
    fi
}

#检查系统
check_sys() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif [ ${IS_MACOS} -eq 1 ]; then
        release="macos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    fi
}

check_crontab_installed_status() {
    if [ -z $(command -v jq) ]; then
        echo -e "jq 依赖没有安装，开始安装..."
        check_root
        if [[ ${release} == "centos" ]]; then
            yum install crond -y
        elif [[ ${release} == "macos" ]]; then
            brew install jq
        else
            apt-get install cron -y
        fi
        if [ -z $(command -v jq) ]; then
            echo -e "jq 依赖安装失败，请检查！" && exit 1
        else
            echo -e "jq 依赖安装成功！"
        fi
    fi
}

#消息推送
send_message() {
    # Server 酱通知
    if [ "${PUSH_KEY}" ]; then
        echo -e "text=${TITLE}&desp=${log_text}" >${PUSH_TMP_PATH}
        push=$(curl -k -s --data-binary @${PUSH_TMP_PATH} "https://sc.ftqq.com/${PUSH_KEY}.send")
        push_code=$(echo ${push} | jq -r ".errno" 2>&1)
        if [ ${push_code} -eq 0 ]; then
            echo -e "【Server 酱推送结果】: 成功\n"
        else
            echo -e "【Server 酱推送结果】: 失败\n"
        fi
    fi

    # Qmsg 酱通知
    if [ "${QMSG_KEY}" ]; then
        result_qmsg_log_text="${TITLE}${log_text}"
        echo -e "msg=${result_qmsg_log_text}" >${PUSH_TMP_PATH}
        push=$(curl -k -s --data-binary @${PUSH_TMP_PATH} "https://qmsg.zendee.cn/send/${QMSG_KEY}")
        push_code=$(echo ${push} | jq -r ".success" 2>&1)
        if [ "${push_code}" == "true" ]; then
            echo -e "【Qmsg 酱推送结果】: 成功\n"
        else
            echo -e "【Qmsg 酱推送结果】: 失败\n"
        fi
    fi

    # TelegramBot 通知
    if [ "${TELEGRAMBOT_TOKEN}" ] && [ "${TELEGRAMBOT_CHATID}" ]; then
        result_tgbot_log_text="${TITLE}${log_text}"
        echo -e "chat_id=${TELEGRAMBOT_CHATID}&parse_mode=Markdown&text=${result_tgbot_log_text}" >${PUSH_TMP_PATH}
        push=$(curl -k -s --data-binary @${PUSH_TMP_PATH} "https://api.telegram.org/bot${TELEGRAMBOT_TOKEN}/sendMessage")
        push_code=$(echo ${push} | grep -o '"ok":true')
        if [ ${push_code} ]; then
            echo -e "【TelegramBot 推送结果】: 成功\n"
        else
            echo -e "【TelegramBot 推送结果】: 失败\n"
        fi
    fi
}

#签到
ssp_autochenkin() {
    if [ "${users_array}" ]; then
        user_count=1
        for user in ${users_array[@]}; do
            domain=$(echo ${user} | awk -F'----' '{print $1}')
            username=$(echo ${user} | awk -F'----' '{print $2}')
            passwd=$(echo ${user} | awk -F'----' '{print $3}')

            # 邮箱、域名脱敏处理
            username_prefix="${username%%@*}"
            username_suffix="${username#*@}"
            username_root="${username#*.}"
            username_text="${username_prefix:0:2}⁎⁎⁎@${username_suffix:0:2}⁎⁎⁎.${username_root}"

            domain_protocol="${domain%%://*}"
            domain_context="${domain##*//}"
            domain_root="${domain##*.}"
            domain_text="${domain_protocol}://${domain_context:0:2}⁎⁎⁎.${domain_root}"

            if [ -z "${domain}" ] || [ -z "${username}" ] || [ -z "${passwd}" ]; then
                echo "账号信息配置异常，请检查配置" && exit 1
            fi

            user_log_text=" - 【用户余额】: ${money} CNY\n"
            user_log_text="${user_log_text} - 【用户限速】: ${node_speedlimit} Mbps\n"
            user_log_text="${user_log_text} - 【总流量】: ${transfer_enable_text}\n"
            user_log_text="${user_log_text} - 【剩余流量】: ${transfer_used_text}\n"
            user_log_text="${user_log_text} - 【已使用流量】: ${last_day_t_text}\n"
            user_log_text="${user_log_text} - 【等级过期时间】: ${class_expire}\n"
            user_log_text="${user_log_text} - 【账户过期时间】: ${expire_in}\n"
            user_log_text="${user_log_text} - 【上次签到时间】: ${last_check_in_time_text}"

            checkin=$(curl -k -s -d "" -b ${COOKIE_PATH} "${domain}/user/checkin")
            chechin_code=$(echo ${checkin} | jq -r ".ret")
            checkin_status=$(echo ${checkin} | jq -r ".msg")

            if [ "${checkin_status}" ]; then
                checkin_log_text=" - 【签到状态】: ${checkin_status}\n"
            else
                checkin_log_text=" - 【签到状态】: 签到失败, 请检查是否存在签到验证码\n"
            fi

            result_log_text="${login_log_text}${checkin_log_text}${user_log_text}"

            # echo -e ${result_log_text}

            # Server 酱通知
            if [ "${PUSH_KEY}" ]; then
                echo -e "text=${TITLE}&desp=${result_log_text}" >${PUSH_TMP_PATH}
                push=$(curl -k -s --data-binary @${PUSH_TMP_PATH} "https://sc.ftqq.com/${PUSH_KEY}.send")
                push_code=$(echo ${push} | jq -r ".errno")
                if [ ${push_code} -eq 0 ]; then
                    echo -e "【Server 酱推送结果】: 成功\n"
                else
                    echo -e "【Server 酱推送结果】: 失败\n"
                fi
            fi

            # Qmsg 酱通知
            if [ "${QMSG_KEY}" ]; then
                result_qmsg_log_text="${TITLE}${result_log_text}"
                echo -e "msg=${result_qmsg_log_text}" >${PUSH_TMP_PATH}
                push=$(curl -k -s --data-binary @${PUSH_TMP_PATH} "https://qmsg.zendee.cn/send/${QMSG_KEY}")
                push_code=$(echo ${push} | jq -r ".success")
                if [ "${push_code}" == "true" ]; then
                    echo -e "【Qmsg 酱推送结果】: 成功\n"
                else
                    echo -e "【Qmsg 酱推送结果】: 失败\n"
                fi
            fi

            # TelegramBot 通知
            if [ "${TELEGRAMBOT_TOKEN}" ] && [ "${TELEGRAMBOT_CHATID}" ]; then
                result_tgbot_log_text="${TITLE}${result_log_text}"
                echo -e "chat_id=${TELEGRAMBOT_CHATID}&parse_mode=Markdown&text=${result_tgbot_log_text}" >${PUSH_TMP_PATH}
                push=$(curl -k -s --data-binary @${PUSH_TMP_PATH} "https://api.telegram.org/bot${TELEGRAMBOT_TOKEN}/sendMessage")
                push_code=$(echo ${push} | grep -o '"ok":true')
                if [ ${push_code} ]; then
                    echo -e "【TelegramBot 推送结果】: 成功\n"
                else
                    echo -e "【TelegramBot 推送结果】: 失败\n"
                fi
            fi

            rm -rf ${COOKIE_PATH}
            rm -rf ${PUSH_TMP_PATH}
        else
            login_log_text="${login_log_text}【签到状态】: 登录失败, 请检查配置\n"
            echo -e ${login_log_text}

            # Server 酱通知
            if [ "${PUSH_KEY}" ]; then
                echo -e "text=${TITLE}&desp=${login_log_text}" >${PUSH_TMP_PATH}
                push=$(curl -k -s --data-binary @${PUSH_TMP_PATH} "https://sc.ftqq.com/${PUSH_KEY}.send")
                push_code=$(echo ${push} | jq -r ".errno")
                if [ ${push_code} -eq 0 ]; then
                    echo -e "【Server 酱推送结果】: 成功\n"
                else
                    echo -e "【Server 酱推送结果】: 失败\n"
                fi
            fi

            # Qmsg 酱通知
            if [ "${QMSG_KEY}" ]; then
                result_qmsg_log_text="${TITLE}${login_log_text}"
                echo -e "msg=${result_qmsg_log_text}" >${PUSH_TMP_PATH}
                push=$(curl -k -s --data-binary @${PUSH_TMP_PATH} "https://qmsg.zendee.cn/send/${QMSG_KEY}")
                push_code=$(echo ${push} | jq -r ".success")
                if [ "${push_code}" == "true" ]; then
                    echo -e "【Qmsg 酱推送结果】: 成功\n"
                else
                    echo -e "【Qmsg 酱推送结果】: 失败\n"
                fi
            fi

            # TelegramBot 通知
            if [ "${TELEGRAMBOT_TOKEN}" ] && [ "${TELEGRAMBOT_CHATID}" ]; then
                result_tgbot_log_text="${TITLE}${login_log_text}"
                echo -e "chat_id=${TELEGRAMBOT_CHATID}&parse_mode=Markdown&text=${result_tgbot_log_text}" >${PUSH_TMP_PATH}
                # push=$(curl -k -s --data-binary @${PUSH_TMP_PATH} "https://api.telegram.org/bot${TELEGRAMBOT_TOKEN}/sendMessage")
                echo -e ${push}
                push_code=$(echo ${push} | grep -o '"ok":true')
                if [ ${push_code} ]; then
                    echo -e "【TelegramBot 推送结果】: 成功\n"
                else
                    echo -e "【TelegramBot 推送结果】: 失败\n"
                fi
            fi

            rm -rf ${COOKIE_PATH}
            rm -rf ${PUSH_TMP_PATH}
        fi
        echo -e "---------------------------------------\n"
    done
else
    echo "用户组环境变量未配置" && exit 1
fi
