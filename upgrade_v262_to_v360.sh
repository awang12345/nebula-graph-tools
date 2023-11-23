#!/bin/bash
# 此脚本用于nebula2.6.2升级到3.6.0
# 参考官网：https://docs.nebula-graph.com.cn/3.6.0/4.deployment-and-installation/3.upgrade-nebula-graph/upgrade-nebula-comm/
SCRIPT_PATH=$(readlink -f $0)
OLD_VERSION_PATTERN='^2\.[5-6]+\.[0-9]+$'
NEW_VERSION='3.6.0'

usage(){
	echo "Usage: ${0} [key=value]* [--key=value]* "
	echo "support parameter keys:"
	echo "--nebula_path              The absolute path of old version nebula."
	echo "--data_backup_path         The data backup path.Source data path is specified by '--data_path' in the nebula-metad.conf and nebula-storaged.conf."
	echo "                           The default backup path is the same as the configuration."
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

CONFIG_BACKUP_FILE_NAME=upgrade_config_bak.tar.gz
DATA_BACKUP_PATH=${data_backup_path}
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


NEBULA_SERVICE=${NEBULA_INSTALL_PATH}/scripts/nebula.service
NEBULA_GRAPHD=${NEBULA_INSTALL_PATH}/bin/nebula-graphd
NEW_NEBULA_SOFT_PATH=${nebula_soft_path:-"/tmp"}
NEW_NEBULA_DOWNLOAD_URL=${new_nebula_download_url:-"https://oss-cdn.nebula-graph.com.cn/package/${NEW_VERSION}/nebula-graph-${NEW_VERSION}.el7.x86_64.tar.gz"}


SCRIPT_DIR=$(dirname ${SCRIPT_PATH})
UTILS_PATH=${SCRIPT_DIR}/utils.sh

# 导入工具文件，主要包含一些通用方法，比如：日志打印
source ${UTILS_PATH} || exit 1

[[ ! -f ${NEBULA_SERVICE} ]] && ERROR_AND_EXIT "The nebula install path is invalid.The path:${NEBULA_SERVICE} not exist!!!" 
[[ ! -f ${NEBULA_GRAPHD} ]] && ERROR_AND_EXIT "The nebula install path is invalid.The path:${NEBULA_GRAPHD} not exist!!!" 


get_nebula_version(){
	local nebula_graphd=${1:-${NEBULA_GRAPHD}}
	local nebula_version=`${nebula_graphd} -version |grep " version " |grep -o '[0-9]*\.[0-9]*\.[0-9]*'`
	[[ -z ${nebula_version} ]] && nebula_version=`${nebula_graphd} -version |grep " version "`
	echo ${nebula_version}
}

current_version=$(get_nebula_version)
INFO "The nebula current version is [${RED}${current_version}${NC}]"

# 检查nebula是否已经升级过
check_nebula_version(){
	[[ "${current_version}" == "${NEW_VERSION}" ]] && ERROR_AND_EXIT "The current version of nebula has been upgraded!!"
	[[ "${current_version}" =~ "${OLD_VERSION_PATTERN}" ]] && [[ "${current_version}" -gt "${NEW_VERSION}" ]] && ERROR_AND_EXIT "The current version of nebula has been upgraded!!"
}


print_param(){
    echo "-------------------------------Upgrade Notes----------------------------------"
    echo "This script refers to the nebula official website 2.6.2 upgrade to 3.6.0 document"
    echo "The upgrade docment url is ${BLUE}https://docs.nebula-graph.com.cn/3.6.0/4.deployment-and-installation/3.upgrade-nebula-graph/upgrade-nebula-comm/${NC}"
    echo "Overall upgrade steps:"
    echo "   ${YELLOW}1.${NC}Backup the config and data ('--data_path' in etc/nebula-storage.conf and etc/nebula-metad.conf)"
    echo "   ${YELLOW}2.${NC}Connect nebula-graphd and execute command 'submit job stats' to statistical spatial data volume."
    echo "   ${YELLOW}3.${NC}Execute shell 'nebula.service stop all' to stop all service.If the service cannot be stopped for more than 20 minutes, the upgrade is aborted"
    echo "   ${YELLOW}4.${NC}Download and install new version nebula package to a different directory than your current nebula.eg:instal to /tmp/nebula_new"
    echo "   ${YELLOW}5.${NC}Use the bin in the new nebula installation directory to override the current version.eg: cp -rf /tmp/nebula_new/bin/* /usr/local/nebula/bin"
    echo "   ${YELLOW}6.${NC}The session_idle_timeout_secs and client_idle_timeout_secs configuration entries in the nebula-graphd.conf file are changed to 28800"
    echo "   ${YELLOW}7.${NC}Startup nebula-metad service for all node.Wait for leader election."
    echo "   ${YELLOW}8.${NC}Startup nebula-grapd service for any node.Connect and execute the command 'SHOW HOSTS meta' 'SHOW META LEADER' To verify that the nebula-metad service started successfully."
    echo "   ${YELLOW}9.${NC}Startup nebula all service for all node.Refer to the following command to verify: "
    echo "          ${BLUE}nebula>${NC} SHOW HOSTS;"
    echo "          ${BLUE}nebula>${NC} SHOW HOSTS storage;"
    echo "          ${BLUE}nebula>${NC} SHOW SPACES;"
    echo "          ${BLUE}nebula>${NC} USE <space_name>"
    echo "          ${BLUE}nebula>${NC} SHOW PARTS;"
    echo "          ${BLUE}nebula>${NC} SUBMIT JOB STATS;"
    echo "          ${BLUE}nebula>${NC} SHOW STATS;"
    echo "          ${BLUE}nebula>${NC} MATCH (v) RETURN v LIMIT 5;"
	echo "${RED}-------------------------------ENV CONFIG---------------------------${NC}"
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
	WARN "Whether to continue (y/n) ?"
	old_stty=$(stty -g) ; stty raw -echo ; opt=$(head -c 1) ; stty $old_stty
	case ${opt} in
		Y|y)
		 break 2
		 ;;
		N|n)
		 INFO "Upgrade abort !!!"
		 exit 1
		 ;;
		*)
		 ;;   
	esac
done

#停止nebula
stop_nebula(){
	# 停止所有旧版本客户端访问
	INFO "Begin to stop nebula all services..."
	${NEBULA_SERVICE} stop all
	[[ $? != 0 ]] && ERROR_AND_EXIT "Stop all server of nebula fail !!!"
	local status=`${NEBULA_SERVICE} status all | grep -c Exited`
	while [[ ${status} -lt 3 ]];do
		INFO "Wait for all services to stop..."
		sleep 3
		status=`${NEBULA_SERVICE} status all | grep -c Exited`
	done
	INFO "Finish stop nebula all server!"
}

#获取真实的数据存储列表，比如 (/usr/local/nebula/data/storage1 /usr/local/nebula/data/storage2)
get_data_path_list(){
	local nebula_path=$1
	local nebula_conf_file_path=${nebula_path}/etc/${2}
	local data_path=$(grep "^--data_path" ${nebula_conf_file_path} | awk -F'=' '{print $NF}')
	[[ -z ${data_path} ]] && ERROR_AND_EXIT "Not found --data_path from ${nebula_conf_file_path}"

	local data_paths=($(echo "$data_path" | tr ',' '\n'))
	local real_data_paths=()
	for path in ${data_paths[@]}
	do
		[[ ${path} == /* ]] || path=${nebula_path}/${path}
		real_data_paths+=(${path})
	done
	echo "${real_data_paths[@]}"
}

# 备份data文件为tar压缩包
backup_data(){
	local data_path=$1
	local backup_dir_path=${DATA_BACKUP_PATH}
	[[ -z ${backup_dir_path} ]] && backup_dir_path=$(dirname ${data_path})
	# data_path=/usr/nebula/data1/storage ，backup_file_name=usr_nebula_data1_storage.tar
	local backup_file_name="$(echo ${data_path//\//_} | sed 's/^_//').tar"
	local backup_file_path=${backup_dir_path}/${backup_file_name}

	if [[ -f ${backup_file_path} ]]; then
		while true;
		do
			WARN "The backup file:${data_path} already exists. Whether to overridde Y/N ?"
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

	INFO "Begin backup ${RED}${data_path}${NC} ==> ${RED}${backup_file_path}${NC}"	

	tar -cvf ${backup_file_path} -C ${data_path} $(ls ${data_path})
	[[ $? != 0 ]] && ERROR_AND_EXIT "Fail backup data dir:${data_path} !"

	INFO "Finish backup ${RED}${data_path}${NC} ==> ${RED}${backup_file_path}${NC}!"
}

#备份所有的metad和storaged的data目录
backup_metad_storage_data(){
	while true;
	do
		WARN "Whether to backup metad and storage data (y/n) ?"
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
	local metad_data_path_list=$(get_data_path_list ${NEBULA_INSTALL_PATH} nebula-metad.conf)
	[[ -z ${metad_data_path_list} ]] && ERROR_AND_EXIT "Not found --data_path in ${NEBULA_INSTALL_PATH}/nebula-metad.conf"
	INFO "Begin backup data of nebula-metad.conf.The data path is ${metad_data_path_list[@]}"
	for data_path in ${metad_data_path_list[@]}
	do
		backup_data ${data_path}
	done
	INFO "Finish backup nebula-metad data."

	local storaged_data_path_list=$(get_data_path_list ${NEBULA_INSTALL_PATH} nebula-storaged.conf)
	[[ -z ${storaged_data_path_list} ]] && ERROR_AND_EXIT "Not found --data_path in ${NEBULA_INSTALL_PATH}/nebula-storaged.conf"
	INFO "Begin backup data of nebula-storaged.conf.The data path is ${storaged_data_path_list[@]}"
	for data_path in ${storaged_data_path_list[@]}
	do
		backup_data ${data_path}
	done
	INFO "Finish backup nebula-storaged data."
}

restore_data(){
	local data_path=$1
	local backup_dir_path=${DATA_BACKUP_PATH}
	[[ -z ${backup_dir_path} ]] && backup_dir_path=$(dirname ${data_path})
	# data_path=/usr/nebula/data1/storage ，backup_file_name=usr_nebula_data1_storage.tar
	local backup_file_name="$(echo ${data_path//\//_} | sed 's/^_//').tar"
	local backup_file_path=${backup_dir_path}/${backup_file_name}

	if [[ ! -f ${backup_file_path} ]]; then
		WARN "Not found backup file:${backup_file_path} for source data:${data_path}."
		return 0
	fi

	INFO "Begin restore ${RED}${backup_file_path}${NC} ==> ${RED}${data_path}${NC}"	
	[[ ! -d ${data_path} ]] && mkdir -p ${data_path}
	tar -xvf ${backup_file_path} -C ${data_path}
	[[ $? != 0 ]] && ERROR_AND_EXIT "Fail backup data dir:${data_path} !"

	INFO "Finish restore ${RED}${backup_file_path}${NC} ==> ${RED}${data_path}${NC}!"
}

# 还原所有数据
restore_metad_storage_data(){
	local metad_data_path_list=$(get_data_path_list ${NEBULA_INSTALL_PATH} nebula-metad.conf)
	[[ -z ${metad_data_path_list} ]] && ERROR_AND_EXIT "Not found --data_path in ${NEBULA_INSTALL_PATH}/nebula-metad.conf"
	INFO "Begin restore data of nebula-metad.conf.The data path is ${metad_data_path_list[@]}"
	for data_path in ${metad_data_path_list[@]}
	do
		restore_data ${data_path}
	done
	INFO "Finish restore nebula-metad data."

	local storaged_data_path_list=$(get_data_path_list ${NEBULA_INSTALL_PATH} nebula-storaged.conf)
	[[ -z ${storaged_data_path_list} ]] && ERROR_AND_EXIT "Not found --data_path in ${NEBULA_INSTALL_PATH}/nebula-storaged.conf"
	INFO "Begin restore data of nebula-storaged.conf.The data path is ${storaged_data_path_list[@]}"
	for data_path in ${storaged_data_path_list[@]}
	do
		restore_data ${data_path}
	done
	INFO "Finish restore nebula-storaged data."
}

# 备份所有配置文件
backup_config(){
	local back_up_file="${NEBULA_INSTALL_PATH}/${CONFIG_BACKUP_FILE_NAME}"
	if [[ -f ${back_up_file} ]];then
		while true;
		do
			WARN "The backup file:${back_up_file} already exists. Whether to overridde (y/n) ?"
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
	INFO "Start backup dir:${RED}${will_back_dirs[@]}${NC}"
	tar -czvf ${back_up_file} -C ${NEBULA_INSTALL_PATH} ${will_back_dirs[@]}
	[[ $? != 0 ]] && ERROR_AND_EXIT "Fail backup config file !!!"
	INFO "Finish backup config file to ${back_up_file}"
}

# 还原配置文件
restore_config(){
	local back_up_file="${NEBULA_INSTALL_PATH}/${CONFIG_BACKUP_FILE_NAME}"
	[[ ! -f ${back_up_file} ]] && ERROR_AND_EXIT "Backup file:${back_up_file} not found!!"
	INFO "Restore backup file:${back_up_file} to ${NEBULA_INSTALL_PATH}"
	tar -zxvf ${back_up_file} -C ${NEBULA_INSTALL_PATH}
	[[ $? != 0 ]] && ERROR_AND_EXIT "Fail restore the backup file !!!"
	INFO "Finish restore backup file !!!"
}

# 安装新版本nebula
install_new_nebula(){
	local install_path=$1
	[[ ! -d ${install_path} ]] && mkdir -p ${install_path}
	local nebula_graphd=${install_path}/bin/nebula-graphd
	# 判断是否已经安装
	if [[ -f ${nebula_graphd} ]];then
		local nebula_version=$(get_nebula_version ${install_path}/bin/nebula-graphd)
		[[ "${nebula_version}" == "${NEW_VERSION}" ]] && INFO "The new nebula was installed" && return 0
		# 目标安装地址已经安装了nebula，并且nebula版本并非是新版
		ERROR_AND_EXIT "The nebula was install.But the version:${nebula_version} not match ${NEW_VERSION} !!"
	fi

	local new_nebula_file_name=$(echo $NEW_NEBULA_DOWNLOAD_URL | awk -F'/' '{print $NF}')
	local new_nebula_file_path=${NEW_NEBULA_SOFT_PATH}/${new_nebula_file_name}
	if [[ ! -f ${new_nebula_file_path} ]];then
		#执行下载逻辑
		INFO "Start download new version nebula by url:${NEW_NEBULA_DOWNLOAD_URL}"
		wget -P ${NEW_NEBULA_SOFT_PATH} ${NEW_NEBULA_DOWNLOAD_URL}
		[[ ! -f ${new_nebula_file_path} ]] && ERROR_AND_EXIT "URL:${NEW_NEBULA_DOWNLOAD_URL} of nebula is invalid!"
		INFO "Finish download new version nebula.The path is ${new_nebula_file_path}"
	fi

	INFO "Start install new version nebula to ${install_path}...."

	case ${new_nebula_file_path} in
		*.rpm)
			sudo rpm -Uvh --prefix=${install_path} ${new_nebula_file_path}
			;;
		*.tar.gz)
			tar -zxvf ${new_nebula_file_path} -C ${install_path} --strip-components 1
			;;
		*)
		 	ERROR_AND_EXIT "Unkown nebula install file:${new_nebula_file_path}"
		 	;;			
	esac

	[[ $? != 0 ]] && ERROR_AND_EXIT "New version nebula install error!"

	INFO "Finish install new version nebula:${RED}$(get_nebula_version ${install_path}/bin/nebula-graphd)${NC}"

}

upgrade(){
	# 执行备份操作
	backup_config
	backup_metad_storage_data

	# 安装新版nebula
	local new_nebula_install_path=/tmp/nebula_${NEW_VERSION}
	install_new_nebula ${new_nebula_install_path}
	# 拷贝将新版的bin目录拷贝到旧目录
	INFO "Copy ${new_nebula_install_path}/bin to ${NEBULA_INSTALL_PATH}/bin"
	cp -rf ${new_nebula_install_path}/bin/* ${NEBULA_INSTALL_PATH}/bin
	INFO "After copy the nebula version:${RED}$(get_nebula_version)${NC}"

	# 修改配置文件nebula-graphd.conf中的session_idle_timeout_secs和client_idle_timeout_secs为28800
	local nebula_graphd_conf_path=${NEBULA_INSTALL_PATH}/etc/nebula-graphd.conf
	[[ -f ${nebula_graphd_conf_path} ]] || ERROR_AND_EXIT "Not found nebula-graphd.conf in dir:${NEBULA_INSTALL_PATH}/etc"
	sed -i 's/session_idle_timeout_secs=0/session_idle_timeout_secs=28800/g' ${nebula_graphd_conf_path}
	sed -i 's/client_idle_timeout_secs=0/client_idle_timeout_secs=28800/g' ${nebula_graphd_conf_path}
	INFO "Update value of ${RED}session_idle_timeout_secs${NC} and ${RED}client_idle_timeout_secs${NC} to ${RED}28800${NC} in the config file:${nebula_graphd_conf_path}"
	grep -E "client_idle_timeout_secs|session_idle_timeout_secs" ${nebula_graphd_conf_path}

	# 拷贝date_time_zonespec.csv到/share/resources下
	local date_time_zonespec_csv_relative_path=share/resources/date_time_zonespec.csv
	local date_time_zonespec_csv_absolute_path=${NEBULA_INSTALL_PATH}/${date_time_zonespec_csv_relative_path}
	local new_nebula_date_time_zonespec_csv_absolute_path=${new_nebula_install_path}/${date_time_zonespec_csv_relative_path}
	[[ ! -f ${date_time_zonespec_csv_absolute_path} ]] \
		&& INFO "Copy ${new_nebula_date_time_zonespec_csv_absolute_path}.csv to ${date_time_zonespec_csv_absolute_path}" \
		&& cp -f ${new_nebula_date_time_zonespec_csv_absolute_path} ${date_time_zonespec_csv_absolute_path}

	INFO "Finish upgraded ！！"
	INFO "${RED}important!!!${NC}Next step you need start all the mated service."
	INFO "${RED}important!!!${NC}Startup one node graphd service after metad srevice started.Connection graphd and execute command 'SHOW HOSTS meta' and 'SHOW META LEADER'"
	INFO "${RED}important!!!${NC}Start all services after confirming that the metad service started successfully"
}

start_nebula_metad(){
	${NEBULA_SERVICE} start metad
	[[ $? != 0 ]] && ERROR_AND_EXIT "Start nebula metad fail!!"
	sleep 3
	local status=`${NEBULA_SERVICE} status metad | grep -c "Listening on"`
	[[ ${status} == 0 ]] && status=`ps -ef |grep -c nebula-metad`
	[[ ${status} == 0 ]] && ERROR_AND_EXIT "Start nebula metad fail!!"
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

# step_2(){
# 	startup_nebula
# }

step_2(){
	stop_nebula
	restore_config
	restore_metad_storage_data
	INFO "After restore the nebula current version is '${RED}$(get_nebula_version)${NC}'."
	startup_nebula
}

INFO "Please select one step"
echo "  ${RED}1.${NC}Stop neblua server and backup as well as upgrade. (${RED}All Node execute${NC})"
echo "  ${RED}2.${NC}Restore the backup file." 
while true;
do
	INFO "Enter a step number 1~2:"
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
