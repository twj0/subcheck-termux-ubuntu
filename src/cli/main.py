#!/usr/bin/env python3
"""
SubCheck 主入口程序
统一的命令行接口
"""

import sys
import argparse
import asyncio
import json
from pathlib import Path

# 添加项目根目录到Python路径
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

from src.core.config_manager import config
from src.core.subscription_parser import SubscriptionParser
from src.core.optimized_network_tester import OptimizedNetworkTester

def setup_logging():
    """设置日志"""
    import logging
    
    log_config = config.get_logging_config()
    
    # 创建日志目录
    log_file = Path(log_config['file'])
    log_file.parent.mkdir(parents=True, exist_ok=True)
    
    # 配置日志
    logging.basicConfig(
        level=getattr(logging, log_config['level']),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file, encoding='utf-8'),
            logging.StreamHandler() if log_config['console'] else logging.NullHandler()
        ]
    )

async def parse_subscriptions(subscription_file: str, output_file: str):
    """解析订阅"""
    print("🔍 解析订阅源...")
    
    # 读取订阅URL列表
    urls = []
    try:
        with open(subscription_file, 'r', encoding='utf-8') as f:
            urls = [line.strip() for line in f if line.strip() and not line.startswith('#')]
    except Exception as e:
        print(f"❌ 读取订阅文件失败: {e}")
        return False
    
    if not urls:
        print("❌ 没有找到有效的订阅URL")
        return False
    
    print(f"📋 发现 {len(urls)} 个订阅源")
    
    # 解析订阅
    parser = SubscriptionParser()
    nodes = await parser.parse_multiple_subscriptions(urls)
    
    if not nodes:
        print("❌ 没有解析到有效节点")
        return False
    
    # 保存结果
    try:
        output_path = Path(output_file)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(nodes, f, ensure_ascii=False, indent=2)
        
        print(f"✅ 解析完成: {len(nodes)} 个节点已保存到 {output_file}")
        return True
        
    except Exception as e:
        print(f"❌ 保存结果失败: {e}")
        return False

async def test_nodes(nodes_file: str, output_file: str, max_nodes: int = None):
    """测试节点"""
    print("🚀 开始网络测试...")
    
    # 读取节点数据
    try:
        with open(nodes_file, 'r', encoding='utf-8') as f:
            nodes = json.load(f)
    except Exception as e:
        print(f"❌ 读取节点文件失败: {e}")
        return False
    
    if not isinstance(nodes, list) or not nodes:
        print("❌ 节点文件格式错误或为空")
        return False
    
    # 过滤有效节点
    valid_nodes = []
    for node in nodes:
        if (node.get('server') and node.get('port') and 
            node.get('type') in ['vless', 'vmess', 'trojan']):
            valid_nodes.append(node)
    
    if not valid_nodes:
        print("❌ 没有找到有效节点")
        return False
    
    print(f"📊 发现 {len(valid_nodes)} 个有效节点")
    
    # 限制测试数量
    if max_nodes and len(valid_nodes) > max_nodes:
        valid_nodes = valid_nodes[:max_nodes]
        print(f"🔢 限制测试数量为 {max_nodes} 个节点")
    
    # 开始测试
    tester = OptimizedNetworkTester()
    
    try:
        await tester.initialize()
        results = await tester.test_multiple_nodes(valid_nodes)
        
        # 保存结果
        output_path = Path(output_file)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(results, f, ensure_ascii=False, indent=2)
        
        # 显示统计信息
        success_results = [r for r in results if r['status'] == 'success']
        success_count = len(success_results)
        total_count = len(results)
        
        print(f"\n📈 测试完成:")
        print(f"   总节点数: {total_count}")
        print(f"   成功节点: {success_count}")
        print(f"   成功率: {success_count/total_count*100:.1f}%")
        print(f"   结果保存: {output_file}")
        
        if success_results:
            # 按延迟排序
            success_results.sort(key=lambda x: x.get('http_latency') or x.get('tcp_latency') or 9999)
            
            print(f"\n🏆 最佳节点 (前5名):")
            for i, result in enumerate(success_results[:5]):
                latency = result.get('http_latency') or result.get('tcp_latency') or 'N/A'
                speed = result.get('download_speed') or 'N/A'
                name = result['name'][:30] if len(result['name']) > 30 else result['name']
                print(f"   {i+1}. {name:<30} {latency:>6}ms {speed:>8}Mbps")
        
        return True
        
    except Exception as e:
        print(f"❌ 测试失败: {e}")
        return False
    finally:
        await tester.cleanup()

async def main():
    """主函数"""
    parser = argparse.ArgumentParser(description='SubCheck - 订阅节点测试工具')
    
    subparsers = parser.add_subparsers(dest='command', help='可用命令')
    
    # 解析命令
    parse_parser = subparsers.add_parser('parse', help='解析订阅源')
    parse_parser.add_argument('subscription_file', help='订阅文件路径')
    parse_parser.add_argument('-o', '--output', default='data/cache/parsed_nodes.json', help='输出文件路径')
    
    # 测试命令
    test_parser = subparsers.add_parser('test', help='测试节点')
    test_parser.add_argument('nodes_file', help='节点文件路径')
    test_parser.add_argument('-o', '--output', default='data/results/test_results.json', help='输出文件路径')
    test_parser.add_argument('-n', '--max-nodes', type=int, help='最大测试节点数')
    
    # 完整流程命令
    full_parser = subparsers.add_parser('run', help='完整流程：解析+测试')
    full_parser.add_argument('subscription_file', help='订阅文件路径')
    full_parser.add_argument('-n', '--max-nodes', type=int, help='最大测试节点数')
    full_parser.add_argument('--nodes-output', default='data/cache/parsed_nodes.json', help='节点输出文件')
    full_parser.add_argument('--results-output', default='data/results/test_results.json', help='结果输出文件')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    # 设置日志
    setup_logging()
    
    try:
        if args.command == 'parse':
            success = await parse_subscriptions(args.subscription_file, args.output)
            
        elif args.command == 'test':
            success = await test_nodes(args.nodes_file, args.output, args.max_nodes)
            
        elif args.command == 'run':
            # 完整流程
            print("🔄 开始完整流程...")
            
            # 1. 解析订阅
            if await parse_subscriptions(args.subscription_file, args.nodes_output):
                # 2. 测试节点
                success = await test_nodes(args.nodes_output, args.results_output, args.max_nodes)
            else:
                success = False
        
        sys.exit(0 if success else 1)
        
    except KeyboardInterrupt:
        print("\n⏹️  用户中断操作")
        sys.exit(1)
    except Exception as e:
        print(f"❌ 程序异常: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
