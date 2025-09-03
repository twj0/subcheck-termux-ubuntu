#!/usr/bin/env node
/**
 * SubCheck Termux-Ubuntu - 格式转换器
 * 支持多种订阅格式转换：Clash、V2Ray、Quantumult等
 * 针对移动端优化的轻量级实现
 */

const fs = require('fs').promises;
const path = require('path');

class FormatConverter {
    constructor() {
        this.supportedFormats = ['clash', 'v2ray', 'quantumult', 'surge'];
    }

    /**
     * 转换节点为Clash格式
     */
    toClashFormat(nodes) {
        const clashConfig = {
            port: 7890,
            'socks-port': 7891,
            'redir-port': 7892,
            'mixed-port': 7893,
            'allow-lan': false,
            mode: 'rule',
            'log-level': 'info',
            'external-controller': '127.0.0.1:9090',
            proxies: [],
            'proxy-groups': [
                {
                    name: '🚀 节点选择',
                    type: 'select',
                    proxies: ['♻️ 自动选择', '🎯 全球直连']
                },
                {
                    name: '♻️ 自动选择',
                    type: 'url-test',
                    proxies: [],
                    url: 'http://www.gstatic.com/generate_204',
                    interval: 300
                },
                {
                    name: '🎯 全球直连',
                    type: 'select',
                    proxies: ['DIRECT']
                }
            ],
            rules: [
                'DOMAIN-SUFFIX,local,DIRECT',
                'IP-CIDR,127.0.0.0/8,DIRECT',
                'IP-CIDR,172.16.0.0/12,DIRECT',
                'IP-CIDR,192.168.0.0/16,DIRECT',
                'IP-CIDR,10.0.0.0/8,DIRECT',
                'IP-CIDR,17.0.0.0/8,DIRECT',
                'IP-CIDR,100.64.0.0/10,DIRECT',
                'GEOIP,CN,DIRECT',
                'MATCH,🚀 节点选择'
            ]
        };

        // 转换节点
        const proxyNames = [];
        for (const node of nodes) {
            const clashProxy = this.nodeToClashProxy(node);
            if (clashProxy) {
                clashConfig.proxies.push(clashProxy);
                proxyNames.push(clashProxy.name);
            }
        }

        // 更新代理组
        clashConfig['proxy-groups'][0].proxies.push(...proxyNames);
        clashConfig['proxy-groups'][1].proxies.push(...proxyNames);

        return clashConfig;
    }

    /**
     * 转换单个节点为Clash代理格式
     */
    nodeToClashProxy(node) {
        const baseProxy = {
            name: this.sanitizeName(node.name || `${node.server}:${node.port}`),
            server: node.server,
            port: parseInt(node.port)
        };

        switch (node.type?.toLowerCase()) {
            case 'vless':
                return {
                    ...baseProxy,
                    type: 'vless',
                    uuid: node.uuid,
                    tls: node.tls !== 'none',
                    network: node.network || 'tcp',
                    'skip-cert-verify': true,
                    ...(node.host && { 'servername': node.host }),
                    ...(node.path && { 'ws-opts': { path: node.path } })
                };

            case 'vmess':
                return {
                    ...baseProxy,
                    type: 'vmess',
                    uuid: node.uuid,
                    alterId: parseInt(node.alterId || 0),
                    cipher: node.cipher || 'auto',
                    network: node.network || 'tcp',
                    tls: !!node.tls,
                    'skip-cert-verify': true,
                    ...(node.host && { 'servername': node.host }),
                    ...(node.path && { 'ws-opts': { path: node.path } })
                };

            case 'trojan':
                return {
                    ...baseProxy,
                    type: 'trojan',
                    password: node.password,
                    sni: node.sni || node.server,
                    'skip-cert-verify': node['skip-cert-verify'] || true
                };

            case 'ss':
                return {
                    ...baseProxy,
                    type: 'ss',
                    cipher: node.cipher || 'aes-256-gcm',
                    password: node.password
                };

            default:
                console.warn(`不支持的节点类型: ${node.type}`);
                return null;
        }
    }

    /**
     * 转换节点为V2Ray订阅格式
     */
    toV2RayFormat(nodes) {
        const links = [];
        for (const node of nodes) {
            const link = this.nodeToV2RayLink(node);
            if (link) {
                links.push(link);
            }
        }
        return Buffer.from(links.join('\n')).toString('base64');
    }

    /**
     * 转换单个节点为V2Ray链接
     */
    nodeToV2RayLink(node) {
        switch (node.type?.toLowerCase()) {
            case 'vless':
                const vlessParams = new URLSearchParams();
                if (node.network) vlessParams.set('type', node.network);
                if (node.tls && node.tls !== 'none') vlessParams.set('security', node.tls);
                if (node.host) vlessParams.set('host', node.host);
                if (node.path) vlessParams.set('path', node.path);
                if (node.sni) vlessParams.set('sni', node.sni);
                
                return `vless://${node.uuid}@${node.server}:${node.port}?${vlessParams.toString()}#${encodeURIComponent(node.name)}`;

            case 'vmess':
                const vmessConfig = {
                    v: '2',
                    ps: node.name,
                    add: node.server,
                    port: node.port.toString(),
                    id: node.uuid,
                    aid: (node.alterId || 0).toString(),
                    scy: node.cipher || 'auto',
                    net: node.network || 'tcp',
                    type: 'none',
                    host: node.host || '',
                    path: node.path || '',
                    tls: node.tls ? 'tls' : ''
                };
                
                return `vmess://${Buffer.from(JSON.stringify(vmessConfig)).toString('base64')}`;

            case 'trojan':
                const trojanParams = new URLSearchParams();
                if (node.sni) trojanParams.set('sni', node.sni);
                if (node['skip-cert-verify']) trojanParams.set('allowInsecure', '1');
                
                return `trojan://${node.password}@${node.server}:${node.port}?${trojanParams.toString()}#${encodeURIComponent(node.name)}`;

            default:
                return null;
        }
    }

    /**
     * 转换节点为Quantumult X格式
     */
    toQuantumultFormat(nodes) {
        const lines = ['[server_remote]', ''];
        
        for (const node of nodes) {
            const qxLine = this.nodeToQuantumultLine(node);
            if (qxLine) {
                lines.push(qxLine);
            }
        }
        
        return lines.join('\n');
    }

    /**
     * 转换单个节点为Quantumult X行格式
     */
    nodeToQuantumultLine(node) {
        const name = this.sanitizeName(node.name);
        
        switch (node.type?.toLowerCase()) {
            case 'vmess':
                return `vmess=${node.server}:${node.port}, method=chacha20-poly1305, password=${node.uuid}, tag=${name}`;
            
            case 'trojan':
                return `trojan=${node.server}:${node.port}, password=${node.password}, tag=${name}`;
            
            default:
                return null;
        }
    }

    /**
     * 清理节点名称
     */
    sanitizeName(name) {
        return name
            .replace(/[^\w\s\-\u4e00-\u9fff]/g, '') // 保留中文、英文、数字、空格、连字符
            .replace(/\s+/g, ' ')
            .trim()
            .substring(0, 50); // 限制长度
    }

    /**
     * 生成移动端优化的配置
     */
    generateMobileOptimizedConfig(nodes, format = 'clash') {
        // 按延迟排序，选择最佳节点
        const sortedNodes = nodes
            .filter(node => node.server && node.port)
            .sort((a, b) => (a.latency || 9999) - (b.latency || 9999))
            .slice(0, 20); // 限制节点数量，减少内存占用

        switch (format.toLowerCase()) {
            case 'clash':
                const clashConfig = this.toClashFormat(sortedNodes);
                // 移动端优化设置
                clashConfig['mixed-port'] = 7890;
                clashConfig['allow-lan'] = false;
                clashConfig['log-level'] = 'warning'; // 减少日志
                clashConfig['ipv6'] = false; // 禁用IPv6以提高连接速度
                return clashConfig;

            case 'v2ray':
                return this.toV2RayFormat(sortedNodes);

            case 'quantumult':
                return this.toQuantumultFormat(sortedNodes);

            default:
                throw new Error(`不支持的格式: ${format}`);
        }
    }

    /**
     * 保存配置到文件
     */
    async saveConfig(config, outputPath, format = 'clash') {
        try {
            let content;
            
            if (format === 'clash') {
                content = `# SubCheck Termux-Ubuntu Generated Config
# Generated at: ${new Date().toISOString()}
# Optimized for mobile devices

${JSON.stringify(config, null, 2)}`;
            } else if (format === 'v2ray') {
                content = config; // Base64 encoded
            } else {
                content = config;
            }

            await fs.writeFile(outputPath, content, 'utf8');
            console.log(`配置已保存到: ${outputPath}`);
            return true;
        } catch (error) {
            console.error(`保存配置失败: ${error.message}`);
            return false;
        }
    }
}

/**
 * 命令行接口
 */
async function main() {
    const args = process.argv.slice(2);
    
    if (args.length < 2) {
        console.log('用法: node format_converter.js <输入JSON文件> <输出格式> [输出文件]');
        console.log('支持格式: clash, v2ray, quantumult');
        process.exit(1);
    }

    const [inputFile, format, outputFile] = args;
    const converter = new FormatConverter();

    try {
        // 读取节点数据
        const data = await fs.readFile(inputFile, 'utf8');
        const nodes = JSON.parse(data);

        if (!Array.isArray(nodes)) {
            throw new Error('输入文件必须包含节点数组');
        }

        console.log(`读取到 ${nodes.length} 个节点`);

        // 转换格式
        const config = converter.generateMobileOptimizedConfig(nodes, format);
        
        // 确定输出文件名
        const defaultExt = format === 'clash' ? 'yaml' : format === 'v2ray' ? 'txt' : 'conf';
        const output = outputFile || `converted_config.${defaultExt}`;

        // 保存配置
        await converter.saveConfig(config, output, format);
        
        console.log(`转换完成: ${format.toUpperCase()} 格式`);
        
    } catch (error) {
        console.error(`转换失败: ${error.message}`);
        process.exit(1);
    }
}

// 如果直接运行此脚本
if (require.main === module) {
    main().catch(console.error);
}

module.exports = FormatConverter;
