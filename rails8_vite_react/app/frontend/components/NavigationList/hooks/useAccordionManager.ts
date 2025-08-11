import { useState } from "react";

type AccordionState = {
  /** トップ階層で開いているindex番号 */
  depth0: number[];
  /** 二階層目で開いているindex番号 */
  depth1: {
    [depth0Index: number]: number[];
  };
};

/** ナビゲーションの番地 */
// 本当はタプル型で厳密にしたいが、再帰コードが書きづらくなるのでとりあえずnumber[]にする
// export type NavIndexes = [number] | [number, number]
type NavIndexes = number[];

export type AccordionManager = {
  /** アコーディオンをトグルする */
  toggle: (navIndexes: NavIndexes) => void;
  /** アコーディオンの開閉フラグの取得 */
  isOpen: (navIndexes: NavIndexes) => boolean;
};

export type UseAccordionManagerOptions = {
  /** 一時的に全て閉じている状態にするか */
  isTemporaryAllClose?: boolean;
};

/**
 * 開閉フラグを管理するhooks
 */
export const useAccordionManager = ({
  isTemporaryAllClose
}: UseAccordionManagerOptions = {}): AccordionManager => {
  const [accordionState, setAccordionState] = useState<AccordionState>({
    depth0: [],
    depth1: {}
  });

  return {
    toggle: (navIndexes) => {
      const [depth0Index, depth1Index] = navIndexes;
      // トップ階層のtoggleの場合
      if (depth1Index == null) {
        if (accordionState.depth0.includes(depth0Index)) {
          setAccordionState({
            ...accordionState,
            depth0: accordionState.depth0.filter(
              (openIndex) => openIndex !== depth0Index
            ),
            depth1: {}
          });
        } else {
          setAccordionState({
            ...accordionState,
            depth0: [depth0Index],
            depth1: {}
          });
        }
        return;
      }

      // 二階層目の場合
      const openIndexes = accordionState.depth1[depth0Index] || [];
      if (openIndexes.includes(depth1Index)) {
        setAccordionState({
          ...accordionState,
          depth1: {
            ...accordionState.depth1,
            [depth0Index]: openIndexes.filter(
              (openIndex) => openIndex !== depth1Index
            )
          }
        });
      } else {
        setAccordionState({
          ...accordionState,
          depth1: {
            ...accordionState.depth1,
            [depth0Index]: openIndexes.concat(depth1Index)
          }
        });
      }
    },
    isOpen: (navIndexes) => {
      if (isTemporaryAllClose) {
        return false;
      }

      const [depth0Index, depth1Index] = navIndexes;
      // トップ階層の場合
      if (depth1Index == null) {
        return accordionState.depth0.includes(depth0Index);
      }
      // 二階層目の場合
      return (accordionState.depth1[depth0Index] || []).includes(depth1Index);
    }
  };
};

