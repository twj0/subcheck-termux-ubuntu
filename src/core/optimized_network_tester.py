#!/usr/bin/env python3
"""
SubCheck 优化版网络测试器
解决Xray代理启动延迟问题，提高并发测试效率
"""

import asyncio
import aiohttp
import json
import time
import socket
import os
import signal
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Set
import logging
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor
import subprocess
import psutil

from config_manager import config

logger = logging.getLogger(__name__)

class ProxyPool:
    """代理池管理器 - 预启动和复用代理进程"""
    
    def __init__(self, pool_size: int = 10):
        self.pool_size = pool_size
        self.available_ports = list(config.get_proxy_port_pool())
        self.active_proxies = {}  # port -> process_info
        self.proxy_queue = asyncio.Queue()
        self.startup_config = config.get_proxy_startup_config()
        
    async def initialize_pool(self):
        """初始化代理池"""
        logger.info(f"初始化代理池，预启动 {self.pool_size} 个代理进程")
        
        # 预启动空闲代理进程
        tasks = []
        for i in range(min(self.pool_size, len(self.available_ports))):
            port = self.available_ports[i]
            tasks.append(self._start_idle_proxy(port))
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        success_count = sum(1 for r in results if r is not False)
        logger.info(f"代理池初始化完成: {success_count}/{len(tasks)} 个代理启动成功")
    
    async def _start_idle_proxy(self, port: int) -> bool:
        """启动空闲代理进程"""
        try:
            # 创建基础SOCKS5代理配置
            config_data = {
                "log": {"loglevel": "error"},
                "inbounds": [{
                    "port": port,
                    "protocol": "socks",
                    "settings": {"auth": "noauth", "udp": True}
                }],
                "outbounds": [{
                    "protocol": "freedom"  # 直连，等待后续配置
                }]
            }
            
            config_file = Path(f"xray_configs/idle_{port}.json")
            config_file.parent.mkdir(exist_ok=True)
            
            with open(config_file, 'w') as f:
                json.dump(config_data, f)
            
            # 启动Xray进程
            process = await asyncio.create_subprocess_exec(
                "xray", "-config", str(config_file),
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL
            )
            
            # 等待进程启动
            await asyncio.sleep(self.startup_config['warmup_time'])
            
            if process.returncode is None:
                self.active_proxies[port] = {
                    'process': process,
                    'config_file': config_file,
                    'status': 'idle',
                    'node': None
                }
                await self.proxy_queue.put(port)
                return True
            else:
                return False
                
        except Exception as e:
            logger.error(f"启动空闲代理失败 port {port}: {e}")
            return False
    
    async def get_proxy(self, node: Dict) -> Optional[int]:
        """获取可用代理端口"""
        try:
            # 从队列获取可用端口
            port = await asyncio.wait_for(self.proxy_queue.get(), timeout=5.0)
            
            # 重新配置代理
            if await self._reconfigure_proxy(port, node):
                self.active_proxies[port]['status'] = 'active'
                self.active_proxies[port]['node'] = node
                return port
            else:
                # 配置失败，重新放回队列
                await self.proxy_queue.put(port)
                return None
                
        except asyncio.TimeoutError:
            logger.warning("代理池已满，创建临时代理")
            return await self._create_temporary_proxy(node)
    
    async def _reconfigure_proxy(self, port: int, node: Dict) -> bool:
        """重新配置代理"""
        try:
            proxy_info = self.active_proxies[port]
            process = proxy_info['process']
            
            # 生成新配置
            config_data = self._generate_proxy_config(node, port)
            
            # 更新配置文件
            with open(proxy_info['config_file'], 'w') as f:
                json.dump(config_data, f)
            
            # 发送HUP信号重新加载配置
            process.send_signal(signal.SIGHUP)
            
            # 等待配置生效
            await asyncio.sleep(0.5)
            
            # 健康检查
            if self.startup_config['health_check']:
                return await self._health_check(port)
            
            return True
            
        except Exception as e:
            logger.error(f"重新配置代理失败 port {port}: {e}")
            return False
    
    async def _create_temporary_proxy(self, node: Dict) -> Optional[int]:
        """创建临时代理"""
        for port in self.available_ports:
            if port not in self.active_proxies:
                try:
                    config_data = self._generate_proxy_config(node, port)
                    config_file = Path(f"xray_configs/temp_{port}.json")
                    
                    with open(config_file, 'w') as f:
                        json.dump(config_data, f)
                    
                    process = await asyncio.create_subprocess_exec(
                        "xray", "-config", str(config_file),
                        stdout=asyncio.subprocess.DEVNULL,
                        stderr=asyncio.subprocess.DEVNULL
                    )
                    
                    await asyncio.sleep(self.startup_config['warmup_time'])
                    
                    if process.returncode is None:
                        self.active_proxies[port] = {
                            'process': process,
                            'config_file': config_file,
                            'status': 'temporary',
                            'node': node
                        }
                        return port
                        
                except Exception as e:
                    logger.error(f"创建临时代理失败 port {port}: {e}")
                    continue
        
        return None
    
    def _generate_proxy_config(self, node: Dict, port: int) -> Dict:
        """生成代理配置"""
        config_data = {
            "log": {"loglevel": "error"},
            "inbounds": [{
                "port": port,
                "protocol": "socks",
                "settings": {"auth": "noauth", "udp": True}
            }],
            "outbounds": [],
            "dns": {
                "servers": ["223.5.5.5", "119.29.29.29", "8.8.8.8"]
            }
        }
        
        # 根据节点类型生成出站配置
        if node['type'] == 'vless':
            outbound = {
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
            
            if node.get('tls') and node['tls'] != 'none':
                outbound["streamSettings"]["security"] = "tls"
                outbound["streamSettings"]["tlsSettings"] = {
                    "serverName": node.get('sni', node['server']),
                    "allowInsecure": True
                }
        
        elif node['type'] == 'vmess':
            outbound = {
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
            
            if node.get('tls'):
                outbound["streamSettings"]["security"] = "tls"
                outbound["streamSettings"]["tlsSettings"] = {
                    "serverName": node.get('host', node['server']),
                    "allowInsecure": True
                }
        
        elif node['type'] == 'trojan':
            outbound = {
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
            raise ValueError(f"不支持的协议: {node['type']}")
        
        config_data["outbounds"] = [
            outbound,
            {"protocol": "freedom", "tag": "direct"}
        ]
        
        return config_data
    
    async def _health_check(self, port: int) -> bool:
        """代理健康检查"""
        try:
            proxy_url = f"socks5://127.0.0.1:{port}"
            
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    "http://www.gstatic.com/generate_204",
                    proxy=proxy_url,
                    timeout=aiohttp.ClientTimeout(total=3)
                ) as response:
                    return response.status in [200, 204]
        except:
            return False
    
    async def release_proxy(self, port: int):
        """释放代理"""
        if port in self.active_proxies:
            proxy_info = self.active_proxies[port]
            
            if proxy_info['status'] == 'temporary':
                # 停止临时代理
                await self._stop_proxy(port)
            else:
                # 重置为空闲状态
                proxy_info['status'] = 'idle'
                proxy_info['node'] = None
                await self.proxy_queue.put(port)
    
    async def _stop_proxy(self, port: int):
        """停止代理进程"""
        if port in self.active_proxies:
            proxy_info = self.active_proxies[port]
            process = proxy_info['process']
            
            try:
                process.terminate()
                await asyncio.wait_for(process.wait(), timeout=3)
            except asyncio.TimeoutError:
                process.kill()
                await process.wait()
            
            # 清理配置文件
            try:
                proxy_info['config_file'].unlink()
            except:
                pass
            
            del self.active_proxies[port]
    
    async def cleanup(self):
        """清理所有代理"""
        logger.info("清理代理池...")
        
        for port in list(self.active_proxies.keys()):
            await self._stop_proxy(port)
        
        # 清理配置目录
        config_dir = Path("xray_configs")
        if config_dir.exists():
            for file in config_dir.glob("*.json"):
                try:
                    file.unlink()
                except:
                    pass

class OptimizedNetworkTester:
    """优化版网络测试器"""
    
    def __init__(self):
        self.proxy_pool = ProxyPool(config.get_proxy_startup_config()['parallel_limit'])
        self.timeouts = config.get_test_timeouts()
        self.speed_config = config.get_speed_test_config()
        
        # 测试端点
        self.test_endpoints = {
            'latency': [
                'http://www.gstatic.com/generate_204',
                'http://cp.cloudflare.com/generate_204',
                'http://detectportal.firefox.com/success.txt'
            ],
            'speed': [
                'http://cachefly.cachefly.net/10mb.test',
                'http://speedtest.tele2.net/10MB.zip',
                'https://speed.cloudflare.com/__down?bytes=10485760'
            ]
        }
    
    async def initialize(self):
        """初始化测试器"""
        await self.proxy_pool.initialize_pool()
    
    async def test_tcp_latency(self, host: str, port: int) -> Optional[float]:
        """TCP连接延迟测试"""
        try:
            start_time = time.time()
            
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(self.timeouts['connect'])
            
            try:
                result = sock.connect_ex((host, port))
                end_time = time.time()
                
                if result == 0:
                    latency = (end_time - start_time) * 1000
                    return round(latency, 2)
            finally:
                sock.close()
                
        except Exception as e:
            logger.debug(f"TCP延迟测试失败 {host}:{port} - {e}")
        
        return None
    
    async def test_http_latency(self, session: aiohttp.ClientSession, proxy_url: str) -> Optional[float]:
        """HTTP延迟测试"""
        latencies = []
        
        for endpoint in self.test_endpoints['latency'][:2]:  # 只测试前2个
            try:
                start_time = time.time()
                
                async with session.get(
                    endpoint,
                    proxy=proxy_url,
                    timeout=aiohttp.ClientTimeout(total=self.timeouts['latency'])
                ) as response:
                    await response.read()
                    end_time = time.time()
                    
                    if response.status in [200, 204]:
                        latency = (end_time - start_time) * 1000
                        latencies.append(latency)
                        
            except Exception as e:
                logger.debug(f"HTTP延迟测试失败 {endpoint} - {e}")
                continue
        
        return round(sum(latencies) / len(latencies), 2) if latencies else None
    
    async def test_download_speed(self, session: aiohttp.ClientSession, proxy_url: str) -> Optional[float]:
        """下载速度测试"""
        speeds = []
        
        for endpoint in self.test_endpoints['speed'][:self.speed_config['endpoints_limit']]:
            try:
                start_time = time.time()
                downloaded_bytes = 0
                
                async with session.get(
                    endpoint,
                    proxy=proxy_url,
                    timeout=aiohttp.ClientTimeout(total=self.timeouts['speed'])
                ) as response:
                    
                    if response.status != 200:
                        continue
                    
                    async for chunk in response.content.iter_chunked(8192):
                        downloaded_bytes += len(chunk)
                        current_time = time.time()
                        
                        # 限制测试时间
                        if current_time - start_time >= self.speed_config['duration']:
                            break
                        
                        # 最小测试大小
                        if downloaded_bytes >= self.speed_config['min_size']:
                            break
                
                elapsed_time = time.time() - start_time
                if elapsed_time > 0 and downloaded_bytes >= self.speed_config['min_size']:
                    speed_bps = (downloaded_bytes * 8) / elapsed_time
                    speed_mbps = speed_bps / (1024 * 1024)
                    speeds.append(speed_mbps)
                    break  # 成功一个就够了
                    
            except Exception as e:
                logger.debug(f"速度测试失败 {endpoint} - {e}")
                continue
        
        return round(max(speeds), 2) if speeds else None
    
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
            tcp_latency = await self.test_tcp_latency(node['server'], node['port'])
            result['tcp_latency'] = tcp_latency
            
            if tcp_latency is None:
                result['error'] = 'TCP连接失败'
                return result
            
            # 2. 获取代理
            proxy_port = await self.proxy_pool.get_proxy(node)
            if proxy_port is None:
                result['error'] = '代理获取失败'
                return result
            
            try:
                proxy_url = f"socks5://127.0.0.1:{proxy_port}"
                
                # 3. HTTP测试
                async with aiohttp.ClientSession(
                    connector=aiohttp.TCPConnector(limit=10)
                ) as session:
                    
                    # HTTP延迟测试
                    http_latency = await self.test_http_latency(session, proxy_url)
                    result['http_latency'] = http_latency
                    
                    # 下载速度测试
                    if http_latency is not None:
                        download_speed = await self.test_download_speed(session, proxy_url)
                        result['download_speed'] = download_speed
                
                # 判断测试结果
                if result['http_latency'] is not None or result['download_speed'] is not None:
                    result['status'] = 'success'
                else:
                    result['error'] = 'HTTP测试全部失败'
                    
            finally:
                # 释放代理
                await self.proxy_pool.release_proxy(proxy_port)
                
        except Exception as e:
            result['error'] = str(e)
            logger.error(f"节点测试异常 {node['name']}: {e}")
        
        return result
    
    async def test_multiple_nodes(self, nodes: List[Dict]) -> List[Dict]:
        """并发测试多个节点"""
        max_nodes = config.get_max_test_nodes()
        max_concurrent = config.calculate_optimal_concurrent()
        
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
        
        # 统计结果
        success_count = sum(1 for r in final_results if r['status'] == 'success')
        logger.info(f"测试完成: {success_count}/{len(final_results)} 个节点成功")
        
        return final_results
    
    async def cleanup(self):
        """清理资源"""
        await self.proxy_pool.cleanup()

async def main():
    """主函数"""
    import sys
    
    if len(sys.argv) < 2:
        print("用法: python optimized_network_tester.py <节点JSON文件> [输出文件]")
        sys.exit(1)
    
    nodes_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else "test_results.json"
    
    # 读取节点数据
    try:
        with open(nodes_file, 'r', encoding='utf-8') as f:
            nodes = json.load(f)
    except Exception as e:
        logger.error(f"读取节点文件失败: {e}")
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
    tester = OptimizedNetworkTester()
    
    try:
        await tester.initialize()
        results = await tester.test_multiple_nodes(valid_nodes)
        
        # 保存结果
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(results, f, ensure_ascii=False, indent=2)
        
        # 显示统计信息
        success_results = [r for r in results if r['status'] == 'success']
        if success_results:
            success_results.sort(key=lambda x: x.get('http_latency') or x.get('tcp_latency') or 9999)
            
            print(f"\n=== 测试完成 ===")
            print(f"成功节点: {len(success_results)}/{len(results)}")
            print(f"结果保存到: {output_file}")
            
            print(f"\n=== 最佳节点 (前10个) ===")
            for i, result in enumerate(success_results[:10]):
                latency = result.get('http_latency') or result.get('tcp_latency') or 'N/A'
                speed = result.get('download_speed') or 'N/A'
                print(f"{i+1:2d}. {result['name'][:30]:30s} {latency:>6}ms {speed:>8}Mbps")
        else:
            print("没有测试成功的节点")
            
    finally:
        await tester.cleanup()

if __name__ == "__main__":
    asyncio.run(main())
