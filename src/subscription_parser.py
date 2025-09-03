#!/usr/bin/env python3
"""
SubCheck Termux-Ubuntu - 订阅解析核心模块
支持多格式订阅解析：Link、Base64、Clash、YAML
针对中国大陆网络环境优化
"""

import asyncio
import aiohttp
import base64
import json
import re
import yaml
import urllib.parse
from typing import List, Dict, Optional, Tuple
from pathlib import Path
import logging
from datetime import datetime, timedelta

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('subscription_parser.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class GitHubProxyManager:
    """GitHub代理管理器 - 中国大陆网络优化"""
    
    PROXIES = [
        "https://gh-proxy.com/",
        "https://ghproxy.net/",
        "https://mirror.ghproxy.com/",
        "https://ghproxy.cc/",
        "https://gh.ddlc.top/",
        "https://slink.ltd/",
        "https://gh.con.sh/",
        "https://cors.isteed.cc/",
        "https://hub.gitmirror.com/",
        ""  # 直连作为备选
    ]
    
    def __init__(self):
        self.working_proxies = []
        self.failed_proxies = set()
    
    async def test_proxy(self, session: aiohttp.ClientSession, proxy: str) -> bool:
        """测试代理可用性"""
        test_url = f"{proxy}https://raw.githubusercontent.com/test/test/main/test.txt"
        try:
            async with session.get(test_url, timeout=aiohttp.ClientTimeout(total=5)) as response:
                return response.status == 200 or response.status == 404  # 404也算正常，说明代理工作
        except:
            return False
    
    async def get_working_proxy(self, session: aiohttp.ClientSession) -> str:
        """获取可用代理"""
        if not self.working_proxies:
            await self.refresh_proxies(session)
        
        if self.working_proxies:
            return self.working_proxies[0]
        return ""  # 返回直连
    
    async def refresh_proxies(self, session: aiohttp.ClientSession):
        """刷新可用代理列表"""
        tasks = []
        for proxy in self.PROXIES:
            if proxy not in self.failed_proxies:
                tasks.append(self.test_proxy(session, proxy))
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        self.working_proxies = []
        for i, result in enumerate(results):
            if result is True:
                self.working_proxies.append(self.PROXIES[i])
        
        logger.info(f"发现 {len(self.working_proxies)} 个可用代理")

class SubscriptionParser:
    """订阅解析器核心类"""
    
    def __init__(self, cache_dir: str = "cache", cache_duration: int = 1800):
        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(exist_ok=True)
        self.cache_duration = cache_duration  # 30分钟缓存
        self.proxy_manager = GitHubProxyManager()
        
        # 支持的协议正则表达式
        self.protocol_patterns = {
            'vless': re.compile(r'vless://([^@]+)@([^:]+):(\d+)(\?[^#]*)?(#.*)?'),
            'vmess': re.compile(r'vmess://([A-Za-z0-9+/=]+)'),
            'trojan': re.compile(r'trojan://([^@]+)@([^:]+):(\d+)(\?[^#]*)?(#.*)?'),
            'ss': re.compile(r'ss://([A-Za-z0-9+/=]+)(@[^#]+)?(#.*)?'),
            'ssr': re.compile(r'ssr://([A-Za-z0-9+/=_-]+)')
        }
    
    def get_cache_path(self, url: str) -> Path:
        """获取缓存文件路径"""
        url_hash = hash(url) % (10**8)  # 简单哈希
        return self.cache_dir / f"sub_{url_hash}.cache"
    
    def is_cache_valid(self, cache_path: Path) -> bool:
        """检查缓存是否有效"""
        if not cache_path.exists():
            return False
        
        cache_time = datetime.fromtimestamp(cache_path.stat().st_mtime)
        return datetime.now() - cache_time < timedelta(seconds=self.cache_duration)
    
    async def fetch_subscription(self, session: aiohttp.ClientSession, url: str) -> Optional[str]:
        """获取订阅内容（支持缓存）"""
        cache_path = self.get_cache_path(url)
        
        # 检查缓存
        if self.is_cache_valid(cache_path):
            try:
                content = cache_path.read_text(encoding='utf-8')
                logger.info(f"使用缓存: {url}")
                return content
            except:
                pass
        
        # 获取新内容
        try:
            # GitHub链接使用代理
            if 'github' in url.lower() or 'raw.githubusercontent.com' in url.lower():
                proxy = await self.proxy_manager.get_working_proxy(session)
                if proxy and not url.startswith(proxy):
                    url = f"{proxy}{url}"
            
            headers = {
                'User-Agent': 'SubCheck-Termux/1.0',
                'Accept': 'text/plain,application/yaml,*/*',
                'Accept-Encoding': 'gzip, deflate'
            }
            
            async with session.get(url, headers=headers, timeout=aiohttp.ClientTimeout(total=30)) as response:
                if response.status == 200:
                    content = await response.text()
                    
                    # 保存到缓存
                    try:
                        cache_path.write_text(content, encoding='utf-8')
                    except:
                        pass
                    
                    logger.info(f"获取成功: {url} ({len(content)} 字符)")
                    return content
                else:
                    logger.warning(f"HTTP {response.status}: {url}")
                    
        except Exception as e:
            logger.error(f"获取失败 {url}: {e}")
        
        return None
    
    def detect_format(self, content: str) -> str:
        """检测订阅格式"""
        content = content.strip()
        
        if not content:
            return 'empty'
        
        # 检测YAML格式
        if content.startswith(('proxies:', 'proxy-groups:', 'rules:')):
            return 'clash_yaml'
        
        # 检测JSON格式
        if content.startswith(('{', '[')):
            try:
                json.loads(content)
                return 'json'
            except:
                pass
        
        # 检测协议链接
        if any(content.startswith(proto) for proto in ['vless://', 'vmess://', 'trojan://', 'ss://', 'ssr://']):
            return 'links'
        
        # 检测Base64编码
        try:
            decoded = base64.b64decode(content + '==')  # 添加padding
            decoded_str = decoded.decode('utf-8')
            if any(proto in decoded_str for proto in ['vless://', 'vmess://', 'trojan://', 'ss://', 'ssr://']):
                return 'base64'
        except:
            pass
        
        return 'unknown'
    
    def decode_base64_content(self, content: str) -> str:
        """解码Base64内容"""
        try:
            # 移除空白字符
            content = re.sub(r'\s', '', content)
            
            # 添加必要的padding
            missing_padding = len(content) % 4
            if missing_padding:
                content += '=' * (4 - missing_padding)
            
            decoded = base64.b64decode(content)
            return decoded.decode('utf-8')
        except Exception as e:
            logger.error(f"Base64解码失败: {e}")
            return ""
    
    def parse_vless_link(self, link: str) -> Optional[Dict]:
        """解析VLESS链接"""
        match = self.protocol_patterns['vless'].match(link)
        if not match:
            return None
        
        uuid, host, port, params, fragment = match.groups()
        
        # 解析参数
        query_params = {}
        if params:
            query_params = dict(urllib.parse.parse_qsl(params[1:]))  # 移除开头的?
        
        # 解析节点名称
        name = urllib.parse.unquote(fragment[1:]) if fragment else f"VLESS-{host}:{port}"
        
        return {
            'name': name,
            'type': 'vless',
            'server': host,
            'port': int(port),
            'uuid': uuid,
            'tls': query_params.get('security', 'none'),
            'network': query_params.get('type', 'tcp'),
            'host': query_params.get('host', ''),
            'path': query_params.get('path', ''),
            'sni': query_params.get('sni', ''),
            'raw_link': link
        }
    
    def parse_vmess_link(self, link: str) -> Optional[Dict]:
        """解析VMess链接 - 增强错误处理"""
        match = self.protocol_patterns['vmess'].match(link)
        if not match:
            return None
        
        try:
            encoded_config = match.group(1)
            
            # 清理Base64字符串
            encoded_config = re.sub(r'[^A-Za-z0-9+/=]', '', encoded_config)
            
            # 添加padding
            missing_padding = len(encoded_config) % 4
            if missing_padding:
                encoded_config += '=' * (4 - missing_padding)
            
            # 解码Base64
            try:
                decoded = base64.b64decode(encoded_config, validate=True)
            except Exception:
                # 尝试URL安全的Base64解码
                encoded_config = encoded_config.replace('-', '+').replace('_', '/')
                decoded = base64.b64decode(encoded_config, validate=True)
            
            # 清理解码后的数据，移除非打印字符
            decoded_str = decoded.decode('utf-8', errors='ignore')
            # 移除控制字符，保留可打印字符
            decoded_str = ''.join(char for char in decoded_str if char.isprintable() or char in '\n\r\t')
            
            # 尝试修复常见的JSON格式问题
            decoded_str = decoded_str.strip()
            if not decoded_str.startswith('{'):
                # 查找第一个{
                start_idx = decoded_str.find('{')
                if start_idx != -1:
                    decoded_str = decoded_str[start_idx:]
            
            if not decoded_str.endswith('}'):
                # 查找最后一个}
                end_idx = decoded_str.rfind('}')
                if end_idx != -1:
                    decoded_str = decoded_str[:end_idx + 1]
            
            config = json.loads(decoded_str)
            
            # 验证必要字段
            server = config.get('add', '').strip()
            if not server:
                return None
            
            # 安全的端口号转换
            port_str = str(config.get('port', '0')).strip()
            try:
                port = int(float(port_str))  # 先转float再转int，处理"443.0"这种情况
                if not (1 <= port <= 65535):
                    return None
            except (ValueError, TypeError):
                return None
            
            # 安全的alterId转换
            aid_str = str(config.get('aid', '0')).strip()
            try:
                alter_id = int(float(aid_str))
            except (ValueError, TypeError):
                alter_id = 0
            
            return {
                'name': config.get('ps', f"VMess-{server}:{port}").strip(),
                'type': 'vmess',
                'server': server,
                'port': port,
                'uuid': config.get('id', '').strip(),
                'alterId': alter_id,
                'cipher': config.get('scy', 'auto').strip(),
                'network': config.get('net', 'tcp').strip(),
                'tls': config.get('tls', '').strip(),
                'host': config.get('host', '').strip(),
                'path': config.get('path', '').strip(),
                'raw_link': link
            }
        except json.JSONDecodeError as e:
            logger.error(f"VMess JSON解析失败: {e}")
            return None
        except Exception as e:
            logger.error(f"VMess解析失败: {e}")
            return None
    
    def parse_trojan_link(self, link: str) -> Optional[Dict]:
        """解析Trojan链接"""
        match = self.protocol_patterns['trojan'].match(link)
        if not match:
            return None
        
        password, host, port, params, fragment = match.groups()
        
        query_params = {}
        if params:
            query_params = dict(urllib.parse.parse_qsl(params[1:]))
        
        name = urllib.parse.unquote(fragment[1:]) if fragment else f"Trojan-{host}:{port}"
        
        return {
            'name': name,
            'type': 'trojan',
            'server': host,
            'port': int(port),
            'password': password,
            'sni': query_params.get('sni', host),
            'skip-cert-verify': query_params.get('allowInsecure', 'false') == 'true',
            'raw_link': link
        }
    
    def parse_links_content(self, content: str) -> List[Dict]:
        """解析链接格式内容"""
        nodes = []
        lines = content.strip().split('\n')
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
            
            node = None
            if line.startswith('vless://'):
                node = self.parse_vless_link(line)
            elif line.startswith('vmess://'):
                node = self.parse_vmess_link(line)
            elif line.startswith('trojan://'):
                node = self.parse_trojan_link(line)
            
            if node:
                nodes.append(node)
        
        return nodes
    
    def parse_clash_yaml(self, content: str) -> List[Dict]:
        """解析Clash YAML格式"""
        try:
            data = yaml.safe_load(content)
            proxies = data.get('proxies', [])
            
            nodes = []
            for proxy in proxies:
                if isinstance(proxy, dict) and 'name' in proxy:
                    # 转换为标准格式
                    node = {
                        'name': proxy['name'],
                        'type': proxy.get('type', 'unknown'),
                        'server': proxy.get('server', ''),
                        'port': proxy.get('port', 0),
                        'raw_config': proxy
                    }
                    
                    # 根据类型添加特定字段
                    if proxy.get('type') == 'vless':
                        node['uuid'] = proxy.get('uuid', '')
                        node['tls'] = proxy.get('tls', False)
                    elif proxy.get('type') == 'vmess':
                        node['uuid'] = proxy.get('uuid', '')
                        node['alterId'] = proxy.get('alterId', 0)
                    elif proxy.get('type') == 'trojan':
                        node['password'] = proxy.get('password', '')
                    
                    nodes.append(node)
            
            return nodes
        except Exception as e:
            logger.error(f"Clash YAML解析失败: {e}")
            return []
    
    async def parse_subscription_url(self, session: aiohttp.ClientSession, url: str) -> List[Dict]:
        """解析单个订阅URL"""
        content = await self.fetch_subscription(session, url)
        if not content:
            return []
        
        format_type = self.detect_format(content)
        logger.info(f"检测到格式: {format_type} - {url}")
        
        if format_type == 'base64':
            content = self.decode_base64_content(content)
            format_type = self.detect_format(content)
        
        if format_type == 'links':
            return self.parse_links_content(content)
        elif format_type == 'clash_yaml':
            return self.parse_clash_yaml(content)
        elif format_type == 'json':
            try:
                data = json.loads(content)
                if isinstance(data, list):
                    return data
            except:
                pass
        
        return []
    
    async def parse_multiple_subscriptions(self, urls: List[str], max_concurrent: int = 10) -> List[Dict]:
        """并发解析多个订阅"""
        semaphore = asyncio.Semaphore(max_concurrent)
        
        async def parse_with_semaphore(session, url):
            async with semaphore:
                return await self.parse_subscription_url(session, url)
        
        async with aiohttp.ClientSession() as session:
            # 初始化代理管理器
            await self.proxy_manager.refresh_proxies(session)
            
            tasks = [parse_with_semaphore(session, url) for url in urls]
            results = await asyncio.gather(*tasks, return_exceptions=True)
            
            all_nodes = []
            for i, result in enumerate(results):
                if isinstance(result, list):
                    all_nodes.extend(result)
                    logger.info(f"订阅 {i+1}/{len(urls)} 解析成功: {len(result)} 个节点")
                else:
                    logger.error(f"订阅 {i+1}/{len(urls)} 解析失败: {result}")
            
            # 去重
            unique_nodes = []
            seen = set()
            for node in all_nodes:
                key = f"{node.get('server', '')}:{node.get('port', 0)}"
                if key not in seen:
                    seen.add(key)
                    unique_nodes.append(node)
            
            logger.info(f"解析完成: 总计 {len(unique_nodes)} 个唯一节点")
            return unique_nodes

async def main():
    """主函数 - 命令行接口"""
    import sys
    
    if len(sys.argv) < 2:
        print("用法: python subscription_parser.py <订阅文件或URL> [输出文件]")
        sys.exit(1)
    
    input_source = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else "parsed_nodes.json"
    
    parser = SubscriptionParser()
    
    # 读取订阅源
    if input_source.startswith(('http://', 'https://')):
        urls = [input_source]
    else:
        try:
            with open(input_source, 'r', encoding='utf-8') as f:
                urls = [line.strip() for line in f if line.strip() and not line.startswith('#')]
        except Exception as e:
            logger.error(f"读取订阅文件失败: {e}")
            sys.exit(1)
    
    # 解析订阅
    nodes = await parser.parse_multiple_subscriptions(urls)
    
    # 保存结果
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(nodes, f, ensure_ascii=False, indent=2)
        
        print(f"解析完成: {len(nodes)} 个节点已保存到 {output_file}")
    except Exception as e:
        logger.error(f"保存结果失败: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
