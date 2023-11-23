# nebula-graph-tools
nebula图数据库工具，目前包含以下工具：
升级脚本，目前支持：1.x升级到3.6.0、2.x升级到3.6.0


## 升级脚本使用说明

### 脚本说明
1. upgrade_v1x_to_v262.sh  ： 升级nebula 1.x到2.6.2
2. upgrade_v20_to_v262.sh  ： 升级nebula 2.0到2.6.2
3. upgrade_v262_to_v360.sh :  升级nebula 2.6.2到3.6.0，升级过程会自动备份storage和etc

### 使用说明
#### 脚本存放位置
1. 1.x升级到2.6.2，需要将upgrade_v1x_to_v262.sh放置在nebula1.x的{nebula_install_path}/scripts目录下
2. 2.0升级到2.6.2，需要将upgrade_v1x_to_v262.sh放置在nebula2.0的{nebula_install_path}/scripts目录下
3. 2.6.2升级到3.6.0，需要将upgrade_v1x_to_v262.sh放置在nebula2.6.2的{nebula_install_path}/scripts目录下
#### 如何执行
1. 先赋予脚本可执行权限，命令：chmod +x upgrade_v1x_to_v262.sh
2. 查看脚本帮助文档，所有的脚本支持--help方式查看使用说明，例如：./upgrade_v1x_to_v262.sh --help
3. 根据文档提示执行升级命令

### nebula 1.x升级到3.6.0（仅测试环境验证）
根据官方说明，1.x不能直接升级到3.6.0，必须先升级到2.6.2再升级到3.6.0
** 注意：** 
此脚本并非在线上验证过，因为在测试环境升级过程中未报错，但是可能在使用的时候会出现key的格式的问题，详见论坛：[3.6版本运行过程中出现：rawKey.size() != expect size](https://discuss.nebula-graph.com.cn/t/topic/14260/8)

### nebula 2.0升级到3.6.0（生产已验证）
根据官方说明，2.0不能直接升级到3.6.0，必须先升级到2.6.2再升级到3.6.0，

### 脚本执行界面截图
![image](https://github.com/awang12345/nebula-graph-tools/assets/14286927/2c746339-8e58-438e-b465-2f69ec96efd8)

![image](https://github.com/awang12345/nebula-graph-tools/assets/14286927/6c3b7993-a808-4faa-9542-970246dbd7df)

![image](https://github.com/awang12345/nebula-graph-tools/assets/14286927/ac738029-605e-4d08-b752-36a596d865f7)

![image](https://github.com/awang12345/nebula-graph-tools/assets/14286927/be075fae-05fe-4826-8b5d-6d5f586fa6d0)










