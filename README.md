# Dify 应用批量迁移工具

这是一个用于在不同 Dify 环境之间批量迁移应用的自动化脚本工具。

[English README](README.en.md)

## 功能特性

- 🚀 **自动化迁移**: 从源环境导出应用并自动导入到目标环境
- 🔧 **灵活配置**: 通过 `.env` 文件配置多种环境参数
- 📋 **选择性迁移**: 支持迁移所有应用或指定特定应用ID
- 🔄 **重试机制**: 内置重试逻辑，提高迁移成功率
- 📁 **备份功能**: 自动创建备份，保存所有导出的应用文件
- 🔍 **日志记录**: 详细的操作日志，支持不同日志级别
- 🧪 **干运行模式**: 测试模式，验证配置而不执行实际迁移
- 📊 **进度跟踪**: 实时显示迁移进度和结果统计

## 待办
- [ ] 多 WorkSpace 迁移  

## 前置要求

### 系统依赖
- `bash` (版本 4.0+)
- `curl`
- `jq` (用于JSON处理)

### macOS 安装依赖
```bash
# 安装 jq
brew install jq
```

### Ubuntu/Debian 安装依赖
```bash
sudo apt-get update
sudo apt-get install curl jq
```

### CentOS/RHEL 安装依赖
```bash
sudo yum install curl jq
```

## 快速开始

### 1. 克隆或下载项目
```bash
git clone <repository-url>
cd batch-migration-dsl
```

### 2. 配置环境文件
```bash
# 复制配置模板
cp env.example .env

# 编辑配置文件
vim .env
```

### 3. 配置必要参数
在 `.env` 文件中设置以下必要参数：

```bash
# 源环境配置
SOURCE_DIFY_URL=https://your-source.dify.ai
SOURCE_BEARER_TOKEN=your_source_bearer_token

# 目标环境配置  
TARGET_DIFY_URL=https://your-target.dify.ai
TARGET_BEARER_TOKEN=your_target_bearer_token
```

### 4. 执行迁移
```bash
# 给脚本执行权限
chmod +x migrate-apps.sh

# 执行完整迁移
./migrate-apps.sh
```

## 详细使用指南

### 环境配置文件说明

| 参数 | 说明 | 必填 | 默认值 |
|------|------|------|--------|
| `SOURCE_DIFY_URL` | 源环境URL | ✅ | - |
| `SOURCE_BEARER_TOKEN` | 源环境访问令牌 | ✅ | - |
| `TARGET_DIFY_URL` | 目标环境URL | ✅ | - |
| `TARGET_BEARER_TOKEN` | 目标环境访问令牌 | ✅ | - |
| `APP_IDS_TO_MIGRATE` | 指定应用ID列表(逗号分隔) | ❌ | 空(迁移所有) |
| `INCLUDE_SECRET` | 是否包含敏感信息 | ❌ | false |
| `BACKUP_DIR` | 备份目录路径 | ❌ | ./backups |
| `LOG_LEVEL` | 日志级别 | ❌ | INFO |
| `MAX_RETRIES` | 最大重试次数 | ❌ | 3 |
| `DRY_RUN` | 干运行模式 | ❌ | false |

### 命令行选项

```bash
./migrate-apps.sh [选项] [环境文件]

选项:
  -h, --help          显示帮助信息
  -c, --config        指定环境配置文件 (默认: .env)
  -a, --apps          指定要迁移的应用ID，用逗号分隔
  -d, --dry-run       干运行模式，仅测试不实际执行
  -v, --verbose       详细输出 (DEBUG模式)
  --export-only       仅导出，不导入
  --import-only       仅导入指定目录中的YAML文件
```

### 使用示例

#### 1. 基本用法
```bash
# 使用默认.env文件进行完整迁移
./migrate-apps.sh
```

#### 2. 指定配置文件
```bash
# 使用自定义配置文件
./migrate-apps.sh -c production.env
```

#### 3. 迁移特定应用
```bash
# 仅迁移指定的应用ID
./migrate-apps.sh -a "app-id-1,app-id-2,app-id-3"
```

#### 4. 干运行测试
```bash
# 测试配置，不执行实际迁移
./migrate-apps.sh -d
```

#### 5. 详细日志输出
```bash
# 启用DEBUG模式查看详细日志
./migrate-apps.sh -v
```

#### 6. 分步执行

**仅导出应用:**
```bash
./migrate-apps.sh --export-only
```

**仅导入应用:**
```bash
# 从默认备份目录导入
./migrate-apps.sh --import-only

# 从指定目录导入
./migrate-apps.sh --import-only ./my-exported-apps
```

#### 7. 组合使用
```bash
# 使用指定配置，详细日志，干运行测试特定应用
./migrate-apps.sh -c staging.env -v -d -a "app-123,app-456"
```

## 获取Bearer Token

### 方法1: 浏览器开发者工具
1. 登录到 Dify 控制台
2. 打开浏览器开发者工具 (F12)
3. 切换到 Network 标签页
4. 执行任意操作触发API请求
5. 查找请求头中的 `authorization: Bearer <token>` 字段
6. 复制 Bearer 后面的 token 值

### 方法2: 浏览器本地存储
1. 登录到 Dify 控制台
2. 打开浏览器开发者工具 (F12)
3. 切换到 Application 标签页
4. 切换到 本地存储空间 标签页
5. 找到 `dify.ai` 域名下的 `access_token` 以及 `refresh_token` 字段
6. 复制 `access_token` 字段的值
7. 复制 `refresh_token` 字段的值

## 目录结构

```
batch-migration-dsl/
├── migrate-apps.sh     # 主迁移脚本
├── env.example         # 环境配置模板
├── .env               # 您的环境配置 (需要创建)
├── example/           # 示例脚本目录
│   ├── export-dsl-curl-example.sh
│   ├── import-dsl-example.sh
│   └── get-all-apps-example.sh
├── backups/          # 备份目录 (自动创建)
│   └── migration_YYYYMMDD_HHMMSS/
└── README.md         # 本文档
```

## 备份和恢复

### 备份位置
所有导出的应用都会保存在备份目录中：
```
backups/migration_20240115_143022/
├── app-id-1_应用名称1.yaml
├── app-id-2_应用名称2.yaml
├── exported_files.list
├── import_success_*.json
└── import_error_*.json
```

### 恢复应用
如果需要恢复或重新导入应用：
```bash
# 从备份目录恢复
./migrate-apps.sh --import-only ./backups/migration_20240115_143022
```

## 故障排除

### 常见问题

#### 1. Token过期
**错误**: `401 Unauthorized` 或 `403 Forbidden`
**解决**: 重新获取Bearer Token并更新.env文件

#### 2. 网络连接问题
**错误**: `curl: (6) Could not resolve host`
**解决**: 检查网络连接和URL配置

#### 3. 应用导入失败
**错误**: 应用格式不兼容
**解决**: 检查源环境和目标环境的Dify版本兼容性

#### 4. 权限不足
**错误**: 无法创建备份目录
**解决**: 确保脚本有写入权限
```bash
chmod +x migrate-apps.sh
mkdir -p backups
```

### 日志分析
启用详细日志来诊断问题：
```bash
./migrate-apps.sh -v 2>&1 | tee migration.log
```

### 测试连接
使用干运行模式测试配置：
```bash
./migrate-apps.sh -d -v
```

## 安全注意事项

1. **Token安全**: 
   - 不要将包含真实Token的.env文件提交到版本控制
   - 定期轮换访问Token
   - 使用最小权限原则

2. **敏感信息**:
   - 默认不导出敏感信息 (`INCLUDE_SECRET=false`)
   - 如需导出敏感信息，请确保备份目录安全

3. **网络安全**:
   - 在安全的网络环境中执行迁移
   - 考虑使用VPN或专用网络

## 性能优化

### 大规模迁移建议

1. **分批迁移**:
```bash
# 分批处理，避免单次迁移过多应用
./migrate-apps.sh -a "app1,app2,app3"
./migrate-apps.sh -a "app4,app5,app6"
```

2. **先导出后导入**:
```bash
# 先全部导出
./migrate-apps.sh --export-only

# 再批量导入
./migrate-apps.sh --import-only
```

3. **调整重试参数**:
```bash
# 在.env中设置更高的重试次数
MAX_RETRIES=5
```

## 贡献指南

欢迎提交Issue和Pull Request来改进这个工具！

### 开发环境设置
```bash
# 克隆项目
git clone <repository-url>
cd batch-migration-dsl

# 创建开发配置
cp env.example .env.dev
```

### 测试
```bash
# 运行测试迁移
./migrate-apps.sh -c .env.dev -d -v
```