# ============================================================
#  RustDesk ID Server 配置
#  此模块在本机（Android 手机）运行 hbbs ID 服务器
#
#  key 的确定顺序（高优先级优先）：
#    1. 环境变量 RD_KEY（service.sh 启动时传入）
#    2. 本文件 SERVER_KEY 变量
#  安装脚本会生成随机 key 并写入本文件 SERVER_KEY，
#  你也可以手动修改。客户端配置时填相同的 key 值。
# ============================================================

# 服务器 key（公钥）。客户端配置时填这个值。
# 注意：服务端必须与客户端 key 一致才能通信。
SERVER_KEY="W8n7Wz7XhPX8wEPUxpnop5T7HGyPGVSF"

# 是否同时启动 hbbr 中继服务器（1=启动, 0=仅 ID 服务器）
# 仅做 ID 服务器时无需中继；如果你还要做中继服务器，改为 1。
ENABLE_RELAY=0

# 中继服务器地址（当 ENABLE_RELAY=0 时，客户端用手机 IP 作为中继地址）
# 若你有独立的中继服务器，填它的 IP 或域名。
RELAY_HOST=""

# hbbs 监听端口（默认 21115-21118，一般不用改）
HBBS_PORT=21116

# hbbr 监听端口（默认 21117，中继用）
HBBR_PORT=21117

# hbbs 运行数据目录（存放密钥对、数据库）。可写即可。
DATA_DIR="/data/local/tmp/rustdesk"

# 日志文件位置
LOG_FILE="$DATA_DIR/rustdesk.log"
