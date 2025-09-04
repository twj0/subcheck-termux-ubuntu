#!/usr/bin/env python3
"""
SubCheck 配置管理器
支持YAML配置文件读取和动态参数计算
"""

import yaml
import os
import math
from pathlib import Path
from typing import Dict, Any, Optional
import logging

logger = logging.getLogger(__name__)

class ConfigManager:
    """配置管理器"""
    
    def __init__(self, config_path: str = "config.yaml"):
        self.config_path = Path(config_path)
        self.config = self._load_config()
        self._validate_config()
    
    def _load_config(self) -> Dict[str, Any]:
        """加载配置文件"""
        if not self.config_path.exists():
            logger.warning(f"配置文件不存在: {self.config_path}，使用默认配置")
            return self._get_default_config()
        
        try:
            with open(self.config_path, 'r', encoding='utf-8') as f:
                config = yaml.safe_load(f)
            logger.info(f"配置文件加载成功: {self.config_path}")
            return config
        except Exception as e:
            logger.error(f"配置文件加载失败: {e}，使用默认配置")
            return self._get_default_config()
    
    def _get_default_config(self) -> Dict[str, Any]:
        """获取默认配置"""
        return {
            'network': {
                'user_bandwidth': 100,
                'auto_concurrent': True,
                'manual_concurrent': 3
            },
            'test': {
                'max_nodes': 50,
                'timeout': {
                    'connect': 8,
                    'latency': 5,
                    'speed': 15,
                    'proxy_start': 3
                },
                'retry': {
                    'count': 1,
                    'delay': 2
                },
                'speed': {
                    'test_duration': 8,
                    'min_size': 1048576,
                    'endpoints_limit': 2
                }
            },
            'proxy': {
                'port_range': {
                    'start': 10800,
                    'end': 10900
                },
                'startup': {
                    'parallel_limit': 10,
                    'warmup_time': 1,
                    'health_check': True
                }
            },
            'github_proxy': {
                'enabled': True,
                'mirrors': [
                    "https://ghfast.top/",
                    "https://gh-proxy.com/",
                    "https://ghproxy.net/"
                ],
                'auto_select': True
            },
            'subscription': {
                'cache': {
                    'enabled': True,
                    'duration': 1800
                },
                'concurrent_parse': 10,
                'deduplication': {
                    'enabled': True,
                    'key_fields': ['server', 'port', 'type']
                }
            },
            'logging': {
                'level': 'INFO',
                'file': 'logs/subcheck.log',
                'console': True
            },
            'performance': {
                'memory_limit': 512,
                'cpu_cores': 0,
                'async_io': {
                    'connector_limit': 100,
                    'connector_limit_per_host': 10
                }
            }
        }
    
    def _validate_config(self):
        """验证配置参数"""
        # 验证网络带宽
        bandwidth = self.get('network.user_bandwidth', 100)
        if bandwidth <= 0:
            logger.warning("用户带宽设置无效，使用默认值100Mbps")
            self.config['network']['user_bandwidth'] = 100
        
        # 验证端口范围
        port_start = self.get('proxy.port_range.start', 10800)
        port_end = self.get('proxy.port_range.end', 10900)
        if port_start >= port_end or port_start < 1024:
            logger.warning("代理端口范围设置无效，使用默认范围")
            self.config['proxy']['port_range'] = {'start': 10800, 'end': 10900}
    
    def get(self, key: str, default: Any = None) -> Any:
        """获取配置值，支持点号分隔的嵌套键"""
        keys = key.split('.')
        value = self.config
        
        for k in keys:
            if isinstance(value, dict) and k in value:
                value = value[k]
            else:
                return default
        
        return value
    
    def calculate_optimal_concurrent(self) -> int:
        """计算最优并发数"""
        if not self.get('network.auto_concurrent', True):
            return self.get('network.manual_concurrent', 3)
        
        bandwidth = self.get('network.user_bandwidth', 100)
        
        # 基于网络带宽计算并发数的公式
        # 假设每个并发连接平均占用5Mbps带宽，使用80%利用率
        optimal_concurrent = max(1, int((bandwidth * 0.8) / 5))
        
        # 限制并发数范围
        min_concurrent = 1
        max_concurrent = min(50, os.cpu_count() * 4) if os.cpu_count() else 20
        
        optimal_concurrent = max(min_concurrent, min(optimal_concurrent, max_concurrent))
        
        logger.info(f"基于{bandwidth}Mbps带宽计算最优并发数: {optimal_concurrent}")
        return optimal_concurrent
    
    def get_proxy_port_pool(self) -> range:
        """获取代理端口池"""
        start = self.get('proxy.port_range.start', 10800)
        end = self.get('proxy.port_range.end', 10900)
        return range(start, end + 1)
    
    def get_github_proxy_mirrors(self) -> list:
        """获取GitHub代理镜像列表"""
        if not self.get('github_proxy.enabled', True):
            return []
        return self.get('github_proxy.mirrors', [])
    
    def get_test_timeouts(self) -> Dict[str, int]:
        """获取测试超时配置"""
        return {
            'connect': self.get('test.timeout.connect', 8),
            'latency': self.get('test.timeout.latency', 5),
            'speed': self.get('test.timeout.speed', 15),
            'proxy_start': self.get('test.timeout.proxy_start', 3)
        }
    
    def get_logging_config(self) -> Dict[str, Any]:
        """获取日志配置"""
        return {
            'level': self.get('logging.level', 'INFO'),
            'file': self.get('logging.file', 'logs/subcheck.log'),
            'console': self.get('logging.console', True)
        }
    
    def should_enable_cache(self) -> bool:
        """是否启用缓存"""
        return self.get('subscription.cache.enabled', True)
    
    def get_cache_duration(self) -> int:
        """获取缓存持续时间"""
        return self.get('subscription.cache.duration', 1800)
    
    def get_max_test_nodes(self) -> int:
        """获取最大测试节点数"""
        return self.get('test.max_nodes', 50)
    
    def get_speed_test_config(self) -> Dict[str, Any]:
        """获取速度测试配置"""
        return {
            'duration': self.get('test.speed.test_duration', 8),
            'min_size': self.get('test.speed.min_size', 1048576),
            'endpoints_limit': self.get('test.speed.endpoints_limit', 2)
        }
    
    def get_proxy_startup_config(self) -> Dict[str, Any]:
        """获取代理启动配置"""
        return {
            'parallel_limit': self.get('proxy.startup.parallel_limit', 10),
            'warmup_time': self.get('proxy.startup.warmup_time', 1),
            'health_check': self.get('proxy.startup.health_check', True)
        }
    
    def update_config(self, key: str, value: Any):
        """更新配置值"""
        keys = key.split('.')
        config = self.config
        
        for k in keys[:-1]:
            if k not in config:
                config[k] = {}
            config = config[k]
        
        config[keys[-1]] = value
        logger.info(f"配置已更新: {key} = {value}")
    
    def save_config(self):
        """保存配置到文件"""
        try:
            with open(self.config_path, 'w', encoding='utf-8') as f:
                yaml.dump(self.config, f, default_flow_style=False, allow_unicode=True)
            logger.info(f"配置已保存到: {self.config_path}")
        except Exception as e:
            logger.error(f"配置保存失败: {e}")

# 全局配置实例
config = ConfigManager()
