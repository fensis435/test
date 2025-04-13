// src/components/Graph/NetworkGraph.js
import { useEffect, useRef, useState } from 'react';
import { MultiDirectedGraph } from 'graphology';
import { Sigma } from 'sigma';
import { NodeSquareProgram } from '@sigma/node-square';
import { EdgeCurvedArrowProgram } from "@sigma/edge-curve";
import { Menu, useContextMenu } from 'react-contexify';
import 'react-contexify/dist/ReactContexify.css';
import { initialGraphData } from '../../lib/graphData';

const MENU_ID = 'network-context-menu';

export default function NetworkGraph({ onNodeSelect, onEdgeSelect }) {
  const containerRef = useRef(null);
  const sigmaRef = useRef(null);
  const graphRef = useRef(null);
  const { show } = useContextMenu({
    id: MENU_ID,
  });

  const [hoveredNode, setHoveredNode] = useState(null);
  const [hoveredEdge, setHoveredEdge] = useState(null);

  useEffect(() => {
    // グラフの作成
    const graph = new MultiDirectedGraph();
    graphRef.current = graph;

    // サンプルデータの読み込み
    initialGraphData.nodes.forEach(node => {
      graph.addNode(node.id, {
        ...node,
        x: Math.random() * 10,  // サンプルの初期位置
        y: Math.random() * 10,
        size: 15,
        type: 'square',  // 四角形のノードを使用
        imageUrl: node.imageUrl || `/images/server.png`,  // デフォルトイメージ
      });
    });

    initialGraphData.edges.forEach(edge => {
      graph.addEdge(edge.source, edge.target, {
        ...edge,
        size: 3,
      });
    });
    initialGraphData.flows.forEach(flow => {
      graph.addEdge(flow.source, flow.target, {
        ...flow,
        color: flow.color,
        type: 'curved',
        curvature: flow.curvature,
        size: 3,
      });
    });

    // Sigmaインスタンスの作成
    const renderer = new Sigma(graph, containerRef.current, {
      defaultNodeType: 'square',
      nodeProgramClasses: {
        square: NodeSquareProgram,
      },
      edgeProgramClasses: {
        curved: EdgeCurvedArrowProgram,
      },
      renderEdgeLabels: true,
    });
    sigmaRef.current = renderer;

    // イベントリスナーの設定
    renderer.on('clickNode', ({ node }) => {
      const nodeData = graph.getNodeAttributes(node);
      onNodeSelect(nodeData);
    });

    renderer.on('clickEdge', ({ edge }) => {
      const edgeData = graph.getEdgeAttributes(edge);
      onEdgeSelect({
        ...edgeData,
        id: edge,
        source: graph.source(edge),
        target: graph.target(edge),
      });
    });

    renderer.on('rightClickNode', (e) => {
      //e.event.preventDefault();
      setHoveredNode(e.node);
      show({
        event: e.event,
        props: {
          type: 'node',
          id: e.node,
        },
      });
    });

    renderer.on('rightClickEdge', (e) => {
      e.event.preventDefault();
      setHoveredEdge(e.edge);
      show({
        event: e.event,
        props: {
          type: 'edge',
          id: e.edge,
        },
      });
    });

    return () => {
      if (sigmaRef.current) {
        sigmaRef.current.kill();
      }
    };
  }, [onNodeSelect, onEdgeSelect, show]);

  const handleItemAction = (action, props) => {
    if (props.type === 'node') {
      const node = graphRef.current.getNodeAttributes(props.id);
      onNodeSelect(node);
    } else if (props.type === 'edge') {
      const edge = props.id;
      const edgeData = graphRef.current.getEdgeAttributes(edge);
      onEdgeSelect({
        ...edgeData,
        id: edge,
        source: graphRef.current.source(edge),
        target: graphRef.current.target(edge),
      });
    }
  };

  return (
    <>
      <div ref={containerRef} style={{ width: '100%', height: '100%' }} />
      
      <Menu id={MENU_ID}>
        <div className="react-contexify__item" onClick={() => handleItemAction('edit')}>
          <div className="react-contexify__item__content">編集</div>
        </div>
        <div className="react-contexify__item" onClick={() => handleItemAction('delete')}>
          <div className="react-contexify__item__content">削除</div>
        </div>
      </Menu>
    </>
  );
}
