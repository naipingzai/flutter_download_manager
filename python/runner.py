#!/usr/bin/env python3
"""
Python Runner - 通过命令行调用 dy_bridge / xhs_bridge 的函数
用法: python3 runner.py <module_name> <function_name> [args_json]
"""
import sys
import json
import os

# 将 python 目录添加到 sys.path
script_dir = os.path.dirname(os.path.abspath(__file__))
if script_dir not in sys.path:
    sys.path.insert(0, script_dir)

def main():
    if len(sys.argv) < 3:
        print(json.dumps({"success": False, "message": "Usage: runner.py <module> <function> [args_json]"}))
        sys.exit(1)

    module_name = sys.argv[1]
    function_name = sys.argv[2]
    args_json = sys.argv[3] if len(sys.argv) > 3 else "[]"

    try:
        # 动态导入模块
        module = __import__(module_name)

        # 获取函数
        func = getattr(module, function_name, None)
        if func is None:
            print(json.dumps({"success": False, "message": f"Function '{function_name}' not found in '{module_name}'"}))
            sys.exit(1)

        # 解析参数
        try:
            args = json.loads(args_json)
            if not isinstance(args, list):
                args = [args]
        except json.JSONDecodeError:
            args = [args_json]

        # 调用函数
        result = func(*args)

        # 输出结果
        if isinstance(result, str):
            print(result)
        elif isinstance(result, (dict, list)):
            print(json.dumps(result, ensure_ascii=False))
        elif isinstance(result, bool):
            print(json.dumps({"success": result}))
        else:
            print(json.dumps({"result": str(result)}))

    except Exception as e:
        print(json.dumps({"success": False, "message": str(e)}))
        sys.exit(1)

if __name__ == "__main__":
    main()
