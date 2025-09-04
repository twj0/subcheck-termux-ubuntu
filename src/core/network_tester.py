#!/usr/bin/env python3
"""
SubCheck Termux-Ubuntu - 网络测速核心模块
专为中国大陆网络环境优化的延迟和带宽测试
集成Xray代理，支持VLESS/VMess/Trojan协议
"""

import asyncio
import aiohttp
import json
import subprocess
import tempfile
import time
import socket
import struct
import os
import signal
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

class XrayManager:
    """Xray代理管理器"""
    
    def __init__(self, xray_path: str = "xray", work_dir: str = "xray_configs"):
        self.xray_path = xray_path
        self.work_dir = Path(work_dir)
        self.work_dir.mkdir(exist_ok=True)
        self.processes = {}  # 存储运行中的xray进程
        
        # 中国大陆优化的DNS服务器
        self.dns_servers = [
            "223.5.5.5",      # 阿里DNS
            "119.29.29.29",   # 腾讯DNS
            "114.114.114.114", # 114DNS
            "8.8.8.8"         # Google DNS (备用)
        ]
    
    def generate_xray_config(self, node: Dict, local_port: int = 10808) -> Dict:
        """生成Xray配置文件"""
        
        # 基础配置模板
        config = {
            "log": {
                "loglevel": "warning"
            },
            "inbounds": [{
                "tag": "socks-in",
                "port": local_port,
                "protocol": "socks",
                "settings": {
                    "auth": "noauth",
                    "udp": True
                }
            }],
            "outbounds": [],
            "dns": {
                "servers": self.dns_servers
            },
            "routing": {
                "rules": [
                    {
                        "type": "field",
                        "ip": ["geoip:private"],
                        "outboundTag": "direct"
                    }
                ]
            }
        }
        
        # 根据节点类型生成出站配置
        if node['type'] == 'vless':
            outbound = {
                "tag": "proxy",
                "protocol": "vless",
                "settings": {
                    "vnext": [{
                        "address": node['server'],
                        "port": node['port'],
                        "users": [{
                            "id": node['uuid'],
                            "encryption": "none"
                        }]
                    }]
                },
                "streamSettings": {
                    "network": node.get('network', 'tcp')
                }
            }
            
            # TLS配置
            if node.get('tls') and node['tls'] != 'none':
                outbound["streamSettings"]["security"] = "tls"
                outbound["streamSettings"]["tlsSettings"] = {
                    "serverName": node.get('sni', node['server']),
                    "allowInsecure": True
                }
            
            # WebSocket配置
            if node.get('network') == 'ws':
                outbound["streamSettings"]["wsSettings"] = {
                    "path": node.get('path', '/'),
                    "headers": {}
                }
                if node.get('host'):
                    outbound["streamSettings"]["wsSettings"]["headers"]["Host"] = node['host']
        
        elif node['type'] == 'vmess':
            outbound = {
                "tag": "proxy",
                "protocol": "vmess",
                "settings": {
                    "vnext": [{
                        "address": node['server'],
                        "port": node['port'],
                        "users": [{
                            "id": node['uuid'],
                            "alterId": node.get('alterId', 0),
                            "security": node.get('cipher', 'auto')
                        }]
                    }]
                },
                "streamSettings": {
                    "network": node.get('network', 'tcp')
                }
            }
            
            # TLS配置
            if node.get('tls'):
                outbound["streamSettings"]["security"] = "tls"
                outbound["streamSettings"]["tlsSettings"] = {
                    "serverName": node.get('host', node['server']),
                    "allowInsecure": True
                }
        
        elif node['type'] == 'trojan':
            outbound = {
                "tag": "proxy",
                "protocol": "trojan",
                "settings": {
                    "servers": [{
                        "address": node['server'],
                        "port": node['port'],
                        "password": node['password']
                    }]
                },
                "streamSettings": {
                    "security": "tls",
                    "tlsSettings": {
                        "serverName": node.get('sni', node['server']),
                        "allowInsecure": node.get('skip-cert-verify', True)
                    }
                }
            }
        
        else:
            raise ValueError(f"不支持的协议类型: {node['type']}")
        
        # 添加直连出站
        config["outbounds"] = [
            outbound,
            {
                "tag": "direct",
                "protocol": "freedom"
            }
        ]
        
        return config
    
    async def start_xray_proxy(self, node: Dict, local_port: int = 10808) -> Optional[str]:
        """启动Xray代理进程"""
        try:
            # 生成配置
            config = self.generate_xray_config(node, local_port)
            
            # 保存配置文件
            config_file = self.work_dir / f"config_{local_port}.json"
            with open(config_file, 'w', encoding='utf-8') as f:
                json.dump(config, f, indent=2, ensure_ascii=False)
            
            # 启动Xray进程
            process = await asyncio.create_subprocess_exec(
                self.xray_path, "-config", str(config_file),
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL
            )
            
            # 等待进程启动
            await asyncio.sleep(2)
            
            # 检查进程是否正常运行
            if process.returncode is None:
                process_id = f"{node['server']}:{node['port']}"
                self.processes[process_id] = {
                    'process': process,
                    'config_file': config_file,
                    'local_port': local_port
                }
                logger.info(f"Xray代理启动成功: {process_id} -> 127.0.0.1:{local_port}")
                return process_id
            else:
                logger.error(f"Xray进程启动失败: {node['server']}:{node['port']}")
                return None
                
        except Exception as e:
            logger.error(f"启动Xray代理失败: {e}")
            return None
    
    async def stop_xray_proxy(self, process_id: str):
        """停止Xray代理进程"""
        if process_id in self.processes:
            process_info = self.processes[process_id]
            process = process_info['process']
            
            try:
                process.terminate()
                await asyncio.wait_for(process.wait(), timeout=5)
            except asyncio.TimeoutError:
                process.kill()
                await process.wait()
            
            # 清理配置文件
            try:
                process_info['config_file'].unlink()
            except:
                pass
            
            del self.processes[process_id]
            logger.info(f"Xray代理已停止: {process_id}")
    
    async def cleanup_all(self):
        """清理所有Xray进程"""
        for process_id in list(self.processes.keys()):
            await self.stop_xray_proxy(process_id)

class NetworkTester:
    """网络测试器 - 中国大陆优化版"""
    
    def __init__(self):
        self.xray_manager = XrayManager()
        
        # 中国大陆测试端点
        self.test_endpoints = {
            'latency': [
                'http://www.gstatic.com/generate_204',  # Google 204
                'http://cp.cloudflare.com/generate_204', # Cloudflare 204
                'http://detectportal.firefox.com/success.txt', # Firefox
                'http://www.msftconnecttest.com/connecttest.txt', # Microsoft
            ],
            'speed': [
                'http://cachefly.cachefly.net/100mb.test',  # CacheFly
                'http://speedtest.tele2.net/100MB.zip',     # Tele2
                'http://proof.ovh.net/files/100Mb.dat',     # OVH
                'https://speed.cloudflare.com/__down?bytes=104857600', # Cloudflare 100MB
            ]
        }
        
        # 超时设置
        self.timeouts = {
            'connect': 10,      # 连接超时
            'latency': 5,       # 延迟测试超时
            'speed': 30         # 速度测试超时
        }
    
    async def test_tcp_latency(self, host: str, port: int, timeout: int = 5) -> Optional[float]:
        """TCP连接延迟测试"""
        try:
            start_time = time.time()
            
            # 创建socket连接
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            
            try:
                result = sock.connect_ex((host, port))
                end_time = time.time()
                
                if result == 0:
                    latency = (end_time - start_time) * 1000  # 转换为毫秒
                    return round(latency, 2)
                else:
                    return None
            finally:
                sock.close()
                
        except Exception as e:
            logger.debug(f"TCP延迟测试失败 {host}:{port} - {e}")
            return None
    
    async def test_http_latency(self, session: aiohttp.ClientSession, url: str, proxy: str = None) -> Optional[float]:
        """HTTP延迟测试 (gen_204)"""
        try:
            connector_kwargs = {}
            if proxy:
                connector_kwargs['proxy'] = proxy
            
            start_time = time.time()
            
            async with session.get(
                url,
                timeout=aiohttp.ClientTimeout(total=self.timeouts['latency']),
                **connector_kwargs
            ) as response:
                await response.read()
                end_time = time.time()
                
                if response.status in [200, 204]:
                    latency = (end_time - start_time) * 1000
                    return round(latency, 2)
                else:
                    return None
                    
        except Exception as e:
            logger.debug(f"HTTP延迟测试失败 {url} - {e}")
            return None
    
    async def test_download_speed(self, session: aiohttp.ClientSession, url: str, proxy: str = None, test_duration: int = 10) -> Optional[float]:
        """下载速度测试"""
        try:
            connector_kwargs = {}
            if proxy:
                connector_kwargs['proxy'] = proxy
            
            start_time = time.time()
            downloaded_bytes = 0
            
            async with session.get(
                url,
                timeout=aiohttp.ClientTimeout(total=self.timeouts['speed']),
                **connector_kwargs
            ) as response:
                
                if response.status != 200:
                    return None
                
                async for chunk in response.content.iter_chunked(8192):
                    downloaded_bytes += len(chunk)
                    current_time = time.time()
                    
                    # 限制测试时间
                    if current_time - start_time >= test_duration:
                        break
            
            elapsed_time = time.time() - start_time
            if elapsed_time > 0 and downloaded_bytes > 0:
                # 计算速度 (Mbps)
                speed_bps = (downloaded_bytes * 8) / elapsed_time
                speed_mbps = speed_bps / (1024 * 1024)
                return round(speed_mbps, 2)
            else:
                return None
                
        except Exception as e:
            logger.debug(f"速度测试失败 {url} - {e}")
            return None
    
    async def test_node_comprehensive(self, node: Dict) -> Dict:
        """综合测试单个节点"""
        result = {
            'name': node.get('name', 'Unknown'),
            'server': node.get('server', ''),
            'port': node.get('port', 0),
            'type': node.get('type', ''),
            'tcp_latency': None,
            'http_latency': None,
            'download_speed': None,
            'status': 'failed',
            'error': None,
            'test_time': datetime.now().isoformat()
        }
        
        try:
            # 1. TCP连接测试
            logger.info(f"测试TCP连接: {node['name']}")
            tcp_latency = await self.test_tcp_latency(node['server'], node['port'])
            result['tcp_latency'] = tcp_latency
            
            if tcp_latency is None:
                result['error'] = 'TCP连接失败'
                return result
            
            # 2. 启动Xray代理
            logger.info(f"启动代理: {node['name']}")
            local_port = 10808 + hash(f"{node['server']}:{node['port']}") % 1000
            process_id = await self.xray_manager.start_xray_proxy(node, local_port)
            
            if process_id is None:
                result['error'] = 'Xray代理启动失败'
                return result
            
            try:
                # 等待代理稳定
                await asyncio.sleep(3)
                
                proxy_url = f"socks5://127.0.0.1:{local_port}"
                
                # 3. HTTP延迟测试
                async with aiohttp.ClientSession() as session:
                    logger.info(f"测试HTTP延迟: {node['name']}")
                    
                    # 尝试多个测试端点
                    http_latencies = []
                    for endpoint in self.test_endpoints['latency']:
                        latency = await self.test_http_latency(session, endpoint, proxy_url)
                        if latency is not None:
                            http_latencies.append(latency)
                    
                    if http_latencies:
                        result['http_latency'] = round(sum(http_latencies) / len(http_latencies), 2)
                    
                    # 4. 下载速度测试
                    logger.info(f"测试下载速度: {node['name']}")
                    
                    # 尝试多个速度测试端点
                    speeds = []
                    for endpoint in self.test_endpoints['speed'][:2]:  # 只测试前2个，节省时间
                        speed = await self.test_download_speed(session, endpoint, proxy_url, 8)
                        if speed is not None and speed > 0:
                            speeds.append(speed)
                    
                    if speeds:
                        result['download_speed'] = round(max(speeds), 2)  # 取最高速度
                
                # 判断测试结果
                if result['http_latency'] is not None or result['download_speed'] is not None:
                    result['status'] = 'success'
                else:
                    result['error'] = 'HTTP测试全部失败'
                    
            finally:
                # 清理代理进程
                await self.xray_manager.stop_xray_proxy(process_id)
                
        except Exception as e:
            result['error'] = str(e)
            logger.error(f"节点测试异常 {node['name']}: {e}")
        
        return result
    
    async def test_multiple_nodes(self, nodes: List[Dict], max_concurrent: int = 3, max_nodes: int = 50) -> List[Dict]:
        """并发测试多个节点"""
        
        # 限制测试节点数量
        if len(nodes) > max_nodes:
            logger.info(f"节点数量过多，限制为前 {max_nodes} 个")
            nodes = nodes[:max_nodes]
        
        semaphore = asyncio.Semaphore(max_concurrent)
        
        async def test_with_semaphore(node):
            async with semaphore:
                return await self.test_node_comprehensive(node)
        
        logger.info(f"开始测试 {len(nodes)} 个节点，并发数: {max_concurrent}")
        
        tasks = [test_with_semaphore(node) for node in nodes]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # 处理异常结果
        final_results = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                final_results.append({
                    'name': nodes[i].get('name', 'Unknown'),
                    'server': nodes[i].get('server', ''),
                    'port': nodes[i].get('port', 0),
                    'type': nodes[i].get('type', ''),
                    'status': 'failed',
                    'error': str(result),
                    'test_time': datetime.now().isoformat()
                })
            else:
                final_results.append(result)
        
        # 清理所有代理进程
        await self.xray_manager.cleanup_all()
        
        # 统计结果
        success_count = sum(1 for r in final_results if r['status'] == 'success')
        logger.info(f"测试完成: {success_count}/{len(final_results)} 个节点成功")
        
        return final_results

async def main():
    """主函数 - 命令行接口"""
    import sys
    
    if len(sys.argv) < 2:
        print("用法: python network_tester.py <节点JSON文件> [输出文件] [最大测试数量]")
        sys.exit(1)
    
    nodes_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else "test_results.json"
    max_nodes = int(sys.argv[3]) if len(sys.argv) > 3 else 50
    
    # 读取节点数据
    try:
        with open(nodes_file, 'r', encoding='utf-8') as f:
            nodes = json.load(f)
    except Exception as e:
        logger.error(f"读取节点文件失败: {e}")
        sys.exit(1)
    
    if not isinstance(nodes, list):
        logger.error("节点文件格式错误，应为数组")
        sys.exit(1)
    
    # 过滤有效节点
    valid_nodes = []
    for node in nodes:
        if (node.get('server') and node.get('port') and 
            node.get('type') in ['vless', 'vmess', 'trojan']):
            valid_nodes.append(node)
    
    logger.info(f"发现 {len(valid_nodes)} 个有效节点")
    
    if not valid_nodes:
        logger.error("没有找到有效节点")
        sys.exit(1)
    
    # 开始测试
    tester = NetworkTester()
    results = await tester.test_multiple_nodes(valid_nodes, max_nodes=max_nodes)
    
    # 保存结果
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(results, f, ensure_ascii=False, indent=2)
        
        # 显示统计信息
        success_results = [r for r in results if r['status'] == 'success']
        if success_results:
            # 按延迟排序
            success_results.sort(key=lambda x: x.get('http_latency') or 9999)
            
            print(f"\n=== 测试完成 ===")
            print(f"成功节点: {len(success_results)}/{len(results)}")
            print(f"结果保存到: {output_file}")
            
            print(f"\n=== 最佳节点 (前10个) ===")
            for i, result in enumerate(success_results[:10]):
                latency = result.get('http_latency', 'N/A')
                speed = result.get('download_speed', 'N/A')
                print(f"{i+1:2d}. {result['name'][:30]:30s} {latency:>6}ms {speed:>8}Mbps")
        else:
            print("没有测试成功的节点")
            
    except Exception as e:
        logger.error(f"保存结果失败: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
