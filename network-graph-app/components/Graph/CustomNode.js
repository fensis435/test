// src/components/Graph/CustomNode.js
import { useEffect, useRef } from 'react';

export default function CustomNode({ graph, renderer }) {
  const loadedImages = useRef(new Map());

  useEffect(() => {
    if (!graph || !renderer) return;

    const loadCustomNodeImages = async () => {
      // ノードごとに画像を読み込む
      graph.forEachNode((nodeId) => {
        const nodeData = graph.getNodeAttributes(nodeId);
        if (nodeData.imageUrl && !loadedImages.current.has(nodeData.imageUrl)) {
          const image = new Image();
          image.src = nodeData.imageUrl;
          image.onload = () => {
            loadedImages.current.set(nodeData.imageUrl, image);
            renderer.refresh();
          };
        }
      });

      // カスタムノードレンダリングの設定
      renderer.setSetting('nodeReducer', (node, data) => {
        const imageUrl = data.imageUrl;
        if (imageUrl && loadedImages.current.has(imageUrl)) {
          const image = loadedImages.current.get(imageUrl);
          return {
            ...data,
            type: 'image',
            image,
          };
        }
        return data;
      });
    };

    loadCustomNodeImages();
    
    return () => {
      // クリーンアップ
      loadedImages.current.clear();
    };
  }, [graph, renderer]);

  return null;
}

