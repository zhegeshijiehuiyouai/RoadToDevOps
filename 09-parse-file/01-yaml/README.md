脚本拷贝自 [https://github.com/jasperes/bash-yaml](https://github.com/jasperes/bash-yaml)

### 用法
拷贝 `yaml.sh` 并导入你的脚本: `source yaml.sh`

脚本提供了两个方法:

- **parse_yaml**: 读取yaml文件并直接输出结果。
- **create_variables**: 读取yaml文件，基于yaml文件的内容创建变量。

### 已知问题
`Null` 必须用 `"attr: "` 来表示。