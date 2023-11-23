#!/bin/bash
# 此脚本用于nebula2.0.x升级到2.6.2
# 升级过程会自动备份配置文件
# 升级失败时可以恢复备份文件
# 参考文档：https://docs.nebula-graph.io/2.6.2/4.deployment-and-installation/3.upgrade-nebula-graph/upgrade-nebula-from-200-to-latest/
# 总体步骤为：
#    1.备份bin、etc、scripts等配置
#    2.下载rpm包，并安装到当前nebula安装目录下
#    3.执行"nebula.service start all"命令重启所有的service
SCRIPT_PATH=$(readlink -f $0)

usage(){
    echo "Usage: ${0} [key=value]* [--key=value]* "
	echo "Usage: ${0} [key=value]* [--key=value]* "
	echo "support parameter keys:"
	echo "--nebula_path              The absolute path of old version nebula."
	echo "--new_nebula_download_url  The new version nebula download url."
	echo "                           Default value is https://oss-cdn.nebula-graph.com.cn/package/${version}/nebula-graph-${version}.el7.x86_64.rpm"
	echo "eg:  "
	echo "  ${0} --nebula_path=/usr/local/nebula"
}

[[ $# == 1 && "${1//-/}" =~ ^h(elp)?$ ]] && usage && exit 1


# 解析参数
while [[ $# > 0 ]]
do
	case $1 in
		(*=*) eval ${1//-/}
		;;
	esac
	shift
done

NEBULA_INSTALL_PATH=${nebula_path:-"/usr/loca/nebula"}

find_old_nebula_install_path(){
	local search_path=$1
	local nebula_graphd_path_list=$(find ${search_path} -name nebula-graphd)
	if [[ ! -z ${nebula_graphd_path_list} ]]; then
		for nebula_graphd_path in ${nebula_graphd_path_list[@]}
		do
			 [[ -f ${nebula_graphd_path} ]] && echo ${nebula_graphd_path/\/bin\/nebula-graphd/} && break
		done
	fi
}

get_nebula_install_path(){
	[[ ! -z ${nebula_path} ]] && echo ${nebula_path} && exit 0
	local nebula_install_path=$(ps -ef|grep -E "(nebula-graphd|nebula-metad|nebula-storaged)" |grep -v "grep"|head -1|grep ".*/bin" -o|sed 's/\/bin//g'|awk '{print $NF}')
	[[ ! -z ${nebula_install_path} ]] && echo ${nebula_install_path} && exit 0
	local dir_path=${SCRIPT_PATH}
	while [[ ${dir_path} != "/" ]];
	do
		dir_path=$(dirname ${dir_path})
		local ct=$(ls -d ${dir_path}/* | grep -c -E "(bin|scripts)")
		if [[ ${ct} -ge 2 ]];then
			nebula_install_path=$(find_old_nebula_install_path ${dir_path})
			[[ ! -z ${nebula_install_path} ]] && echo ${nebula_install_path} && exit 0
		fi
	done
}

NEBULA_INSTALL_PATH=$(get_nebula_install_path)
[[ ! -d ${NEBULA_INSTALL_PATH} ]] && ERROR_AND_EXIT "The nebula install path cannot be recognized.Please specify the installation path. eg: ${0} --nebula_path=/usr/local/nebula"


OLD_VERSION_PATTERN='^2\.0+\.[0-9]+$'
NEW_VERSION='2.6.2'
UPGRADE_VERSION=2
BACKUP_FILE_NAME=upgrade_2.0.x_to_2.6.2_config_bak.tar.gz


NEBULA_SERVICE=${NEBULA_INSTALL_PATH}/scripts/nebula.service
NEBULA_GRAPHD=${NEBULA_INSTALL_PATH}/bin/nebula-graphd
NEW_NEBULA_SOFT_PATH=${nebula_soft_path:-"/tmp"}
NEW_NEBULA_DOWNLOAD_URL=${new_nebula_download_url:-"https://oss-cdn.nebula-graph.com.cn/package/${NEW_VERSION}/nebula-graph-${NEW_VERSION}.el7.x86_64.rpm"}


SCRIPT_DIR=$(dirname ${SCRIPT_PATH})
UTILS_PATH=${SCRIPT_DIR}/utils.sh

# 导入工具文件，主要包含一些通用方法，比如：日志打印
source ${UTILS_PATH} || exit 1

[[ ! -f ${NEBULA_SERVICE} ]] && ERROR_AND_EXIT "The nebula install path is invalid.The path:${NEBULA_SERVICE} not exist!!!" 
[[ ! -f ${NEBULA_GRAPHD} ]] && ERROR_AND_EXIT "The nebula install path is invalid.The path:${NEBULA_GRAPHD} not exist!!!" 


get_nebula_version(){
	local nebula_version=`${NEBULA_GRAPHD} -version |grep " version " |grep -o '[0-9]*\.[0-9]*\.[0-9]*'`
	[[ -z ${nebula_version} ]] && nebula_version=`${NEBULA_GRAPHD} -version |grep " version "`
	echo ${nebula_version}
}

current_version=$(get_nebula_version)
INFO "The nebula current version is [ ${RED}${current_version}${NC} ]"

# 检查nebula是否已经升级过
check_nebula_version(){
	[[ "${current_version}" == "${NEW_VERSION}" ]] && ERROR_AND_EXIT "The current version of nebula has been upgraded!!"
	[[ "${current_version}" =~ "${OLD_VERSION_PATTERN}" ]] && [[ "${current_version}" -gt "${NEW_VERSION}" ]] && ERROR_AND_EXIT "The current version of nebula has been upgraded!!"
}


print_param(){
    echo "-------------------------------Upgrade Notes----------------------------------"
    echo "This script refers to the nebula official website 2.0.x upgrade to 2.6.2 document"
    echo "The upgrade docment url is ${BLUE}https://docs.nebula-graph.com.cn/2.6.2/4.deployment-and-installation/3.upgrade-nebula-graph/upgrade-nebula-from-200-to-latest//${NC}"
    echo "Overall upgrade steps:"
    echo "   ${YELLOW}1.${NC}Backup the config"
    echo "   ${YELLOW}2.${NC}Download rpm package and install to the current nebula installation directory"
    echo "   ${YELLOW}3.${NC}Execute shell command 'nebula.service start all' to start all nebula service"
	echo "-------------------------------ENV CONFIG-------------------------------------"
	echo "            nebula_path = ${NEBULA_INSTALL_PATH}"
	echo "        current_version = ${current_version}"
	echo "        upgrade_version = ${NEW_VERSION}"
	echo "  utils_shell_file_path = ${UTILS_PATH}"
	echo "    nebula_service_path = ${NEBULA_SERVICE}"
	echo "     nebula_graphd_path = ${NEBULA_GRAPHD}"
	echo "new_nebula_download_url = ${NEW_NEBULA_DOWNLOAD_URL}"	
    echo "----------------------------------END------------------------------------------"
}
# 打印参数
print_param


WARN "Check that the ENV config are correct."

while true;
do
	WARN "Whether to continue (Y/N) ?"
	old_stty=$(stty -g) ; stty raw -echo ; opt=$(head -c 1) ; stty $old_stty
	case ${opt} in
		Y|y)
		 break 2
		 ;;
		N|n)
		 ERROR "Terminate the upgrade!!!"
		 exit 1
		 ;;
		*)
		 ;;   
	esac
done

#停止nebula
stop_nebula(){
	# 停止所有旧版本客户端访问
	INFO "Stop nebula all server..."
	${NEBULA_SERVICE} stop all
	[[ $? != 0 ]] && ERROR_AND_EXIT "Stop all server of nebula fail !!!"
	local status=`${NEBULA_SERVICE} status all | grep -c Exited`
	while [[ ${status} -lt 3 ]];do
		sleep 1
		INFO "Wait for stop all service..."
		status=`${NEBULA_SERVICE} status all | grep -c Exited`
	done
	INFO "Finish stop nebula all server!"
}

back_up_config(){
	local back_up_file="${NEBULA_INSTALL_PATH}/${BACKUP_FILE_NAME}"
	if [[ -f ${back_up_file} ]];then
		WARN "The backup file:${back_up_file} already exists."
		while true;
		do
			WARN "Whether to overridde Y/N ?"
			old_stty=$(stty -g) ; stty raw -echo ; opt=$(head -c 1) ; stty $old_stty
			case ${opt} in
				Y|y)
				 break
				 ;;
				N|n)
				 return 0
				 ;;
				*)
				 ;;   
			esac
		done
	fi	

	local back_dirs=(etc bin scripts share meta)
	INFO "Start backup ${back_dirs[@]} of ${NEBULA_INSTALL_PATH}...."

	local will_back_dirs=()
	for back_dir in ${back_dirs[@]};
	do
		[[ -d ${NEBULA_INSTALL_PATH}/${back_dir} ]] && will_back_dirs+=("${back_dir}")
	done
	[[ -z "${will_back_dirs[@]}" ]] && ERROR_AND_EXIT "Not found valid config for backup !!!"
	INFO "Start backup ${will_back_dirs[@]}"
	tar -czvf ${back_up_file} -C ${NEBULA_INSTALL_PATH} ${will_back_dirs[@]}
	INFO "Finish backup config file to ${back_up_file}"
}

restore_config(){
	local back_up_file="${NEBULA_INSTALL_PATH}/${BACKUP_FILE_NAME}"
	[[ ! -f ${back_up_file} ]] && ERROR_AND_EXIT "Backup file:${back_up_file} not found!!"
	INFO "Restore backup file:${back_up_file} to ${NEBULA_INSTALL_PATH}"
	tar -zxvf ${back_up_file} -C ${NEBULA_INSTALL_PATH}
	[[ $? != 0 ]] && ERROR_AND_EXIT "Fail restore the backup file !!!"
	INFO "Finish restore backup file !!!"
}

upgrade(){
	back_up_config
	[[ $? != 0 ]] && ERROR_AND_EXIT "Fail backup nebula config file !!"
	new_nebula_file_name=$(echo $NEW_NEBULA_DOWNLOAD_URL | awk -F'/' '{print $NF}')
	new_nebula_file_path=${NEW_NEBULA_SOFT_PATH}/${new_nebula_file_name}
	if [[ ! -f ${new_nebula_file_path} ]];then
		#执行下载逻辑
		INFO "Start download new version nebula by url:${NEW_NEBULA_DOWNLOAD_URL}"
		wget -P ${NEW_NEBULA_SOFT_PATH} ${NEW_NEBULA_DOWNLOAD_URL}
		[[ ! -f ${new_nebula_file_path} ]] && ERROR_AND_EXIT "URL:${NEW_NEBULA_DOWNLOAD_URL} of nebula is invalid!"
		INFO "Finish download new version nebula.The path is ${new_nebula_file_path}"
	fi

	INFO "Start upgraded...."

	sudo rpm -Uvh --prefix=${NEBULA_INSTALL_PATH} ${new_nebula_file_path}
	[[ $? != 0 ]] && ERROR_AND_EXIT "New version nebula install error!"

	INFO "Finish upgraded !!"

}

#停止nebula
startup_nebula(){
	# 停止所有旧版本客户端访问
	INFO "Start nebula all server..."
	${NEBULA_SERVICE} start all
	[[ $? != 0 ]] && ERROR_AND_EXIT "Start all server of nebula fail !!!"
	sleep 1
	${NEBULA_SERVICE} status all
}

step_1(){
	check_nebula_version
	stop_nebula
	upgrade
}

step_2(){
	stop_nebula
	restore_config
	INFO "After restore the nebula current version is '${RED}$(get_nebula_version)${NC}'."
	startup_nebula
}

INFO "Please select one step"
echo "  1.Stop neblua server and backup as well as upgrade. (Notice:All cluster server need to execute first)"
echo "  2.[Upgrade Fail] Restore the backup file." 
while true;
do
	echo "Enter a step number 1~2:"
	old_stty=$(stty -g) ; stty raw -echo ; step_num=$(head -c 1) ; stty $old_stty
	case ${step_num} in
		1)
		 step_1
		 exit 0
		 ;;
		2)
		 step_2
		 exit 0
		 ;;
        q)
		 echo "bye bye !!"
		 exit 0
		 ;;
		*)
		 ;;   
	esac
done

