// src/utils/graphData.js
export const initialGraphData = {
  nodes: [
    { 
      id: 'server1', 
      label: 'Webサーバー',
      type: 'server',
      ipAddress: '192.168.1.10',
      subnet: '255.255.255.0',
      openPorts: [80, 443, 22],
      software: ['Nginx 1.18', 'Ubuntu 20.04'],
      firewallRules: ['Allow HTTP', 'Allow HTTPS', 'Allow SSH'],
      imageUrl: '/images/web-server.png'
    },
    { 
      id: 'server2', 
      label: 'DBサーバー',
      type: 'server',
      ipAddress: '192.168.1.20',
      subnet: '255.255.255.0',
      openPorts: [3306, 22],
      software: ['MySQL 8.0', 'Ubuntu 20.04'],
      firewallRules: ['Allow MySQL', 'Allow SSH'],
      imageUrl: '/images/db-server.png'
    },
    { 
      id: 'server3', 
      label: 'APIサーバー',
      type: 'server',
      ipAddress: '192.168.1.30',
      subnet: '255.255.255.0',
      openPorts: [8080, 22],
      software: ['Node.js 14', 'Ubuntu 20.04'],
      firewallRules: ['Allow API', 'Allow SSH'],
      imageUrl: '/images/api-server.png'
    },
    { 
      id: 'router1', 
      label: 'メインルーター',
      type: 'router',
      ipAddress: '192.168.1.1',
      subnet: '255.255.255.0',
      openPorts: [80, 443, 22],
      software: ['Cisco IOS 15.2'],
      firewallRules: ['Default Deny', 'Allow Internal'],
      imageUrl: '/images/router.png'
    },
  ],
  edges: [
    { 
      source: 'router1', 
      target: 'server1', 
      label: 'Web接続',
      protocol: 'HTTP/HTTPS',
      bandwidth: '1Gbps' 
    },
    { 
      source: 'server1', 
      target: 'server2', 
      label: 'DB接続',
      protocol: 'MySQL',
      bandwidth: '1Gbps'
    },
    { 
      source: 'server1', 
      target: 'server3', 
      label: 'API接続',
      protocol: 'HTTP/REST',
      bandwidth: '1Gbps'
    },
  ]
};

