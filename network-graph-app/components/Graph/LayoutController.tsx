import Sigma from "sigma";
import { ForceAtlas2Layout } from "graphology-layout-forceatlas2";
import { NoverlapLayout } from "graphology-layout-noverlap";
import { MultiDirectedGraph } from "graphology";

class LayoutController {
  private fa2: ForceAtlas2Layout;
  private noverlap: NoverlapLayout;
  private isRunning = false;

  constructor(graph: MultiDirectedGraph) {
    this.fa2 = new ForceAtlas2Layout(graph, {
      settings: {
        gravity: 0.05,
        scalingRatio: 10,
        slowDown: 5,
        barnesHutOptimize: true
      }
    });

    this.noverlap = new NoverlapLayout(graph, {
      maxIterations: 100,
      margin: 5
    });
  }

  async start() {
    this.isRunning = true;
    
    // ForceAtlas2で大まかな配置
    await this.runForceAtlas2(500);
    
    // Noverlapで重なり解消
    await this.runNoverlap();
    
    this.isRunning = false;
  }

  private runForceAtlas2(iterations: number): Promise<void> {
    return new Promise((resolve) => {
      let count = 0;
      const interval = setInterval(() => {
        this.fa2.step();
        renderer.refresh();
        
        if (++count >= iterations) {
          clearInterval(interval);
          resolve();
        }
      }, 16);
    });
  }

  private runNoverlap(): Promise<void> {
    return new Promise((resolve) => {
      this.noverlap.assign({
        onConverged: () => resolve()
      });
      renderer.refresh();
    });
  }
}
