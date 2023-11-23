#!/bin/bash
# 此shell脚本用于将nebula 1.x版本升级到2.x的版本
# 参考文档：https://docs.nebula-graph.com.cn/2.6.2/4.deployment-and-installation/3.upgrade-nebula-graph/upgrade-nebula-graph-to-latest/
SCRIPT_PATH=$(readlink -f $0)
SCRIPT_DIR_PATH=$(dirname "$SCRIPT_PATH")
DEFAULT_OLD_NEBULA_PATH=$(dirname "$SCRIPT_DIR_PATH")
usage(){
        echo "Usage: ${0} [key=value]* [--key=value]* "
        echo "support parameter keys:"
        echo "--config                         The absolute path of config file."
        echo "                                 Default value is ${SCRIPT_DIR_PATH}/upgrade_config.conf."
        echo "--old_nebula_path                The absolute path of old version nebula."
        echo "                                 Default value is ${DEFAULT_OLD_NEBULA_PATH}."
        echo "--new_nebula_path                The absolute path of new version nebula."
        echo "                                 Default value is /usr/loca/nebula_new."
        echo "--new_nebula_version             The version of new version nebula."
        echo "                                 Default value is 2.6.2."
    echo "--new_nebula_storage_data_path   The data path of storage."
        echo "                                 Default value is {new_nebula_path}/data/storage"
        echo "--new_nebula_soft_path           The dir absolute path of nebula soft file."
        echo "                                 Default value is /usr/local/nebula_soft."
        echo "--new_nebula_download_url        The new version nebula download url."
        echo "                                 Default value is https://oss-cdn.nebula-graph.com.cn/package/${version}/nebula-graph-${version}.el7.x86_64.rpm"
        echo ""
        echo "eg:  "
        echo "  ${0} --config=$(pwd)/upgrade_config.conf"
        echo "  ${0} --old_nebula_path=/usr/local/nebula --new_nebula_path=/usr/local/nebula_new --new_nebula_version=2.6.2"
}

[[ $# == 1 && "${1//-/}" =~ ^h(elp)?$ ]] && usage && exit 1


# use config file 
[[ -z ${config} ]] && config=${SCRIPT_DIR_PATH}/upgrade_config.conf
[[ -f ${config} ]] && echo "Use config:${config} to upgrade" && eval "$(grep '=' ${config})"

# 解析参数
while [[ $# > 0 ]]
do
	case $1 in
		(*=*) eval ${1//-/}
		;;
	esac
	shift
done


OLD_VERSION_PATTERN='^(1|2020)\.[0-9]+\.[0-9]+$'
NEW_VERSION_PATTERN='^2\.[0-9]+\.[0-9]+$'
UPGRADE_VERSION=1
NEBULA_SERVICE_FILE_RELATIVE_PATH=scripts/nebula.service
NEBULA_GRAPHD_FILE_RELATIVE_PATH=bin/nebula-graphd

NEW_VERSION_NEBULA_INSTALL_PATH=${new_nebula_path:-"/usr/local/nebula_new"}
OLD_VERSION_NEBULA_INSTALL_PATH=${old_nebula_path:-"/usr/loca/nebula"}

NEW_NEBULA_STORAGE_DATA_PATH=${new_nebula_storage_data_path:-"data/storage"}

# 获取nebula的版本号
get_nebula_version(){
	local nebula_path=$1
	local nebula_graphd_path=${nebula_path}/${NEBULA_GRAPHD_FILE_RELATIVE_PATH}
	${nebula_graphd_path} -version |grep " version " |grep -o '[0-9]*\.[0-9]*\.[0-9]*'
}

find_old_nebula_install_path(){
	local nebula_graphd_path_list=$(find /usr/local -name nebula-graphd)
	if [[ ! -z ${nebula_graphd_path_list} ]]; then
		for nebula_graphd_path in ${nebula_graphd_path_list[@]}
		do
			nebula_version=$(${nebula_graphd_path} -version |grep " version " |grep -o '[0-9]*\.[0-9]*\.[0-9]*')
			[[ "${nebula_version}" =~ ${OLD_VERSION_PATTERN} ]] && echo ${nebula_graphd_path/\/bin\/nebula-graphd/} && break
		done
	fi
}

# 根据nebula的进程号识别path
set_old_nebula_install_path(){
	if [[ -z ${old_nebula_path} ]]; then
		OLD_VERSION_NEBULA_INSTALL_PATH=$(ps -ef|grep -E "(nebula-graphd|nebula-metad|nebula-storaged)" |grep -v "grep"|head -1|grep ".*/bin" -o|sed 's/\/bin//g'|awk '{print $NF}')
		if [[ -z ${OLD_VERSION_NEBULA_INSTALL_PATH} ]]; then
			OLD_VERSION_NEBULA_INSTALL_PATH=$(find_old_nebula_install_path)
		else
			local nebula_version=$(get_nebula_version ${OLD_VERSION_NEBULA_INSTALL_PATH})
			[[ ! "${nebula_version}" =~ ${OLD_VERSION_PATTERN} ]] && OLD_VERSION_NEBULA_INSTALL_PATH=$(find_old_nebula_install_path)	
		fi
		[[ -z ${OLD_VERSION_NEBULA_INSTALL_PATH} ]] && OLD_VERSION_NEBULA_INSTALL_PATH="/usr/local/nebula"
	fi
}

set_old_nebula_install_path


NEW_NEBULA_VERSION=${new_nebula_version:-"2.6.2"}
NEW_NEBULA_SOFT_PATH=${new_nebula_soft_path:-"/usr/local/nebula_soft"}
NEW_NEBULA_DOWNLOAD_URL=${new_nebula_download_url:-"https://oss-cdn.nebula-graph.com.cn/package/${NEW_NEBULA_VERSION}/nebula-graph-${NEW_NEBULA_VERSION}.el7.x86_64.rpm"}
NEW_NEBULA_CONSOLE_DOWNLOAD_URL="https://github.com/vesoft-inc/nebula-console/releases/download/v${NEW_NEBULA_VERSION}/nebula-console-linux-amd64-v${NEW_NEBULA_VERSION}"

OLD_VERSION_NEBULA_SERVICE=${OLD_VERSION_NEBULA_INSTALL_PATH}/${NEBULA_SERVICE_FILE_RELATIVE_PATH}
NEW_VERSION_NEBULA_SERVICE=${NEW_VERSION_NEBULA_INSTALL_PATH}/${NEBULA_SERVICE_FILE_RELATIVE_PATH}

SCRIPT_DIR=$(dirname ${SCRIPT_PATH})
UTILS_PATH=${SCRIPT_DIR}/utils.sh

print_param(){
	echo "-------------------------------ENV CONFIG---------------------------"
	echo "                old_nebula_path = ${OLD_VERSION_NEBULA_INSTALL_PATH}"
	echo "                new_nebula_path = ${NEW_VERSION_NEBULA_INSTALL_PATH}"
    echo "  new_nebula_storaged_data_path = ${NEW_NEBULA_STORAGE_DATA_PATH}"
	echo "        new_nebula_download_url = ${NEW_NEBULA_DOWNLOAD_URL}"
	echo "          utils_shell_file_path = ${UTILS_PATH}"
	echo "old_version_nebula_service_path = ${OLD_VERSION_NEBULA_SERVICE}"
	echo "new_version_nebula_service_path = ${NEW_VERSION_NEBULA_SERVICE}"
	echo "-------------------------------END----------------------------------"
}
# 打印参数
print_param
# 导入工具文件，主要包含一些通用方法，比如：日志打印
source ${UTILS_PATH} || exit 1

WARN "Check that the ENV config are correct."

while true;
do
	WARN "Whether to continue Y/N ?"
	old_stty=$(stty -g) ; stty raw -echo ; opt=$(head -c 1) ; stty ${old_stty}
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


#检测nebula的版本
check_nebula_version(){
	local nebula_path=$1
	local nebula_version_pattern=$2
	local nebula_version=$(get_nebula_version ${nebula_path})
	[[ -z ${nebula_version} ]] && ERROR_AND_EXIT 'Nebula version not avaliable for ${nebula_path}'
	[[ "${nebula_version}" =~ ${nebula_version_pattern} ]] ||  ERROR_AND_EXIT "Nebula version:${nebula_version} not match ${nebula_version_pattern}.Please check nebula path!"
	INFO "Nebula version is ${nebula_version} for path:${nebula_path}"
}
# 这里主要检测nebula目录是否正确，是否为nebula安装目录
check_nebula(){
	local nebula_path=$1
	[[ -d ${nebula_path} ]] || ERROR_AND_EXIT "$nebula_path not exit!"
	local check_file_list=(${NEBULA_SERVICE_FILE_RELATIVE_PATH} ${NEBULA_GRAPHD_FILE_RELATIVE_PATH})
	for check_file in ${check_file_list[@]};
	do
		local file_path=${nebula_path}/${check_file}
		[[ -f ${file_path} ]] || ERROR_AND_EXIT "Nebula install path:$nebula_path is invalid.Not found ${file_path}!"
		[[ -x ${file_path} ]] || ERROR_AND_EXIT "${file_path} is not executable!"
	done
}
#检测旧版本nebula
check_old_version_nebula(){
	INFO "start check old version nebula...."
	# 检测旧版本安装目录是否正确
	check_nebula ${OLD_VERSION_NEBULA_INSTALL_PATH}

	# 检测就版本的version是否符合规则
	check_nebula_version ${OLD_VERSION_NEBULA_INSTALL_PATH} ${OLD_VERSION_PATTERN}

	INFO "finish check old version nebula."
}
# 安装新版本的nebula
install_new_version_nebula(){
	local nebula_path=${NEW_VERSION_NEBULA_INSTALL_PATH}
	# 先确保安装目录为空
	file_count=$(ls ${nebula_path} | wc -l)
	[[ ${file_count} == 0 ]] || ERROR_AND_EXIT "${nebula_path} is not empty directory!"
	# 判断安装文件是否存在
	local new_nebula_file_name=$(echo $NEW_NEBULA_DOWNLOAD_URL | awk -F'/' '{print $NF}')
	local new_nebula_file_path=${NEW_NEBULA_SOFT_PATH}/${new_nebula_file_name}
	if [[ ! -f ${new_nebula_file_path} ]];then
		#执行下载逻辑
		INFO "start download new version nebula by url:${NEW_NEBULA_DOWNLOAD_URL}"
		wget -P ${NEW_NEBULA_SOFT_PATH} ${NEW_NEBULA_DOWNLOAD_URL}
		[[ ! -f ${new_nebula_file_path} ]] && ERROR_AND_EXIT "URL:${NEW_NEBULA_DOWNLOAD_URL} of nebula is invalid!"
		INFO "finish download new version nebula.The path is ${new_nebula_file_path}"
	fi
	INFO "start install new nebula:${new_nebula_file_path} to path:${NEW_VERSION_NEBULA_INSTALL_PATH}"
	sudo rpm -ivh --prefix=${NEW_VERSION_NEBULA_INSTALL_PATH} ${new_nebula_file_path}
	[[ $? != 0 ]] && ERROR_AND_EXIT "Nebula install error!"
	INFO "finish install new nebula to path:${NEW_VERSION_NEBULA_INSTALL_PATH}"
}
#停止旧版本nebula
stop_old_nebula(){
	# 停止所有旧版本客户端访问
	INFO "start stop old version nebula graphd..."
	${OLD_VERSION_NEBULA_SERVICE} stop graphd
	[[ $? != 0 ]] && ERROR_AND_EXIT "Stop the old version nebula error!"
	local status=`${OLD_VERSION_NEBULA_SERVICE} status graphd | grep -c Exited`
	while [[ ${status} < 1 ]];do
		sleep 1
		INFO "Wait for stop graphd..."
		status=`${OLD_VERSION_NEBULA_SERVICE} status graphd | grep -c Exited`
	done	
	INFO "finish stop old version nebula graphd.Start stop all service"
	${OLD_VERSION_NEBULA_SERVICE} stop all
	[[ $? != 0 ]] && ERROR_AND_EXIT "Stop all service of old version nebula error!"
	status=`${OLD_VERSION_NEBULA_SERVICE} status all | grep -c Exited`
	while [[ ${status} < 3 ]];do
		sleep 1
		INFO "Wait for stop all service..."
		status=`${OLD_VERSION_NEBULA_SERVICE} status all | grep -c Exited`
	done
	INFO "finish stop all service of old version nebula!"
}

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

#获取真实的数据存储地址，比如 /usr/local/nebula/data/storage1,/usr/local/nebula/data/storage2
get_real_storaged_data_path(){
	local nebula_path=$1
	local path_list=$(get_data_path_list ${nebula_path} nebula-storaged.conf)
	[[ -z ${path_list} ]] && ERROR_AND_EXIT "Not found data path from ${nebula_path}/etc/nebula-storaged.conf"
	local real_path=${path_list[0]}
	for (( i=1; i<${#path_list[@]}; i++ ))
	do
		real_path+=",${path_list[$i]}"
	done
	echo ${real_path}	
}

# 新版本安装检测
check_new_version_nebula(){
	INFO "start check new version nebula...."
	[[ "${NEW_NEBULA_VERSION}" =~ ${NEW_VERSION_PATTERN} ]] || ERROR_AND_EXIT "The new nebula version not support.Only support version:${NEW_VERSION_PATTERN}"
	# 先判断是否已经安装
	$(check_nebula ${NEW_VERSION_NEBULA_INSTALL_PATH})
	if [[ $? != 0 ]];then
		# 安装nebula
		install_new_version_nebula
	fi
	# storage目录必须要为空
	local path_list=$(get_data_path_list ${NEW_VERSION_NEBULA_INSTALL_PATH} nebula-storaged.conf)
	[[ -z ${path_list} ]] && ERROR_AND_EXIT "Not found data path from ${nebula_conf_path}/etc/nebula-storaged.conf"
	for storage_path in ${path_list[@]}
	do
		[[ ! -d ${storage_path} ]] || [[ $(ls ${storage_path} | wc -l) == 0 ]] || ERROR_AND_EXIT "The storage data path is not empty.The path is ${storage_path}"
	done
	INFO "finish check new version nebula."
}

# 升级前准备
copy_metad_conf_from_old_to_new(){
	# 拷贝配置文件
	INFO "Copy etc from old to new "
	cp -rf ${OLD_VERSION_NEBULA_INSTALL_PATH}/etc ${NEW_VERSION_NEBULA_INSTALL_PATH}/
	#拷贝 metad 数据、配置文件到新目录
	local new_version_meta_data_path=$(get_data_path_list ${NEW_VERSION_NEBULA_INSTALL_PATH} nebula-metad.conf)
	mkdir -p ${new_version_meta_data_path}
	#获取就版本meta文件存储路径
	local old_version_meta_data_path=$(get_data_path_list ${OLD_VERSION_NEBULA_INSTALL_PATH} nebula-metad.conf)
	[[ -z ${old_version_meta_data_path} ]] && exit 1
	INFO "Copy meta data from old to new nebula."
	INFO "The old meta data path is:${old_version_meta_data_path}"
	INFO "The new meta data path is:${new_version_meta_data_path}"
	cp -rf ${old_version_meta_data_path}/*  ${new_version_meta_data_path}

    # 指定storage的数据目录
    # 修改配置文件nebula-storaged.conf中的--data_path
	local nebula_storaged_conf_path=${NEW_VERSION_NEBULA_INSTALL_PATH}/etc/nebula-storaged.conf
	[[ -f ${nebula_storaged_conf_path} ]] || ERROR_AND_EXIT "Not found nebula-storaged.conf in dir:${NEW_VERSION_NEBULA_INSTALL_PATH}/etc"
	sed -i "s|^--data_path=.*|--data_path=${NEW_NEBULA_STORAGE_DATA_PATH}|g" ${nebula_storaged_conf_path}
	INFO "Update value of ${RED}--data_path${NC} to ${RED}${NEW_NEBULA_STORAGE_DATA_PATH}${NC} in the config file:${nebula_storaged_conf_path}"
	grep -E "data_path" ${nebula_storaged_conf_path}    

	# 创建新版本 storaged 数据目录
	local new_version_storage_data_path=($(get_data_path_list ${NEW_VERSION_NEBULA_INSTALL_PATH} nebula-storaged.conf))
	for data_path in ${new_version_storage_data_path[@]}
	do
		INFO "mkdir storaged data path : ${data_path}"
		mkdir -p ${data_path}
	done	
}

start_new_nebula_metad(){
	${NEW_VERSION_NEBULA_SERVICE} start metad
	[[ $? != 0 ]] && ERROR_AND_EXIT "Start new version nebula metad fail!!"
	sleep 3
	local status=`${NEW_VERSION_NEBULA_SERVICE} status metad | grep -c "Listening on"`
	[[ ${status} == 0 ]] && status=`ps -ef |grep -c nebula-metad`
	[[ ${status} == 0 ]] && ERROR_AND_EXIT "Start new version nebula metad fail!!"
}

upgrade_new_nebula_storage(){
	local new_nebula_db_upgrader=${NEW_VERSION_NEBULA_INSTALL_PATH}/bin/db_upgrader
	[[ ! -f ${new_nebula_db_upgrader} || ! -x ${new_nebula_db_upgrader} ]] && ERROR_AND_EXIT "Nebula db_upgrader is not exit.The path is ${new_nebula_db_upgrader}"
	local old_version_storage_data_path_list=$(get_real_storaged_data_path ${OLD_VERSION_NEBULA_INSTALL_PATH} nebula-storaged.conf)
	[[ -z ${old_version_storage_data_path_list} ]] && exit 1
	local new_version_storage_data_path_list=$(get_real_storaged_data_path ${NEW_VERSION_NEBULA_INSTALL_PATH} nebula-storaged.conf)
	[[ -z ${new_version_storage_data_path_list} ]] && exit 1
	local meta_conf=${NEW_VERSION_NEBULA_INSTALL_PATH}/etc/nebula-metad.conf
	local upgrade_meta_server=$(grep "^--meta_server_addrs" ${meta_conf} | awk -F'=' '{print $2}')
	[[ -z ${upgrade_meta_server} ]] && ERROR_AND_EXIT "Not found '--meta_server_addrs' option from ${meta_conf}"

	INFO "----upgrade config parameter----------"
	INFO "src_db_path = ${old_version_storage_data_path_list}"
	INFO "dst_db_path = ${new_version_storage_data_path_list}"
	INFO "upgrade_meta_server = ${upgrade_meta_server}"
	INFO "upgrade_version = ${UPGRADE_VERSION}"
	INFO "--------------------------------------"

	WARN "Check that the upgrade config parameters are correct."

	while true;
	do
		WARN "Whether to perform the upgrade operation (y/n) ?"
		old_stty=$(stty -g) ; stty raw -echo ; opt=$(head -c 1) ; stty ${old_stty}
		case ${opt} in
			Y|y)
			 break
			 ;;
			N|n)
			 ERROR "Terminate the upgrade!!!"
			 exit 1
			 ;;
			*)
			 ;;   
		esac
	done

	INFO "Start perform the upgrade....."

	${new_nebula_db_upgrader} \
	--src_db_path=${old_version_storage_data_path_list} \
	--dst_db_path=${new_version_storage_data_path_list} \
	--upgrade_meta_server=${upgrade_meta_server} \
	--upgrade_version=${UPGRADE_VERSION}

	[[ $? != 0 ]] && ERROR_AND_EXIT "Upgrade fail !!!"
	INFO "Finish upgrade nebula !!!"

}

start_new_nebula_storage(){
	INFO "Start setup new version nebula storaged..."
	${NEW_VERSION_NEBULA_SERVICE} start storaged
	[[ $? != 0 ]] && ERROR_AND_EXIT "Storaged start fail!"
	sleep 1
	${NEW_VERSION_NEBULA_SERVICE} status storaged
}

start_new_nebula_graphd(){
	INFO "Start setup new version nebula graphd..."
	${NEW_VERSION_NEBULA_SERVICE} start graphd
	[[ $? != 0 ]] && ERROR_AND_EXIT "Graphd start fail!"
	sleep 1
	${NEW_VERSION_NEBULA_SERVICE} status graphd
}


# 步骤1，需要先在每台机器上进行执行
step_1(){
	INFO "Start step 1..........."
	check_old_version_nebula
	check_new_version_nebula
	stop_old_nebula
	copy_metad_conf_from_old_to_new
	INFO "Success finish step 1 !!!"
}

# 启动每台机器的metad服务，并检测是否成功
step_2(){
	INFO "Start step 2..........."
	check_new_version_nebula
	start_new_nebula_metad
	INFO "Success finish step 2 !!!"
}
# 进行正在的升级操作，执行升级命令
step_3(){
	check_new_version_nebula
	check_nebula_version ${NEW_VERSION_NEBULA_INSTALL_PATH} ${NEW_VERSION_PATTERN}
	upgrade_new_nebula_storage
}
# 进行正在的升级操作，执行升级命令
step_4(){
	start_new_nebula_storage
}
# 进行正在的升级操作，执行升级命令
step_5(){
	start_new_nebula_graphd
}

echo "Please select one step:"
echo "	${RED}1.${NC}Prepare before upgrading.Includes checking and stopping old services and copying the metad configuration to the new version of nebula (Notice:All cluster server need to execute first)"
echo "	${RED}2.${NC}Start metad service of new version nebula"
echo "	${RED}3.${NC}Perform upgrade that will execute upgrade command"
echo "	${RED}4.${NC}Start storaged service of new version nebula"
echo "	${RED}5.${NC}Start graphd service of new version nebula"
while true;
do
	echo "Enter a valid step number 1~5:"
	old_stty=$(stty -g) ; stty raw -echo ; step_num=$(head -c 1) ; stty ${old_stty}
	case ${step_num} in
		1)
		 step_1
		 break
		 ;;
		2)
		 step_2
		 break
		 ;;
		3)
		 step_3
		 break
		 ;;
		4)
		 step_4
		 break
		 ;;
		5)
		 step_5
		 break
		 ;;  
		q)
		 INFO "byte byte !"
		 break
		 ;; 
		*)
		 ;;   
	esac
done

exit $?
