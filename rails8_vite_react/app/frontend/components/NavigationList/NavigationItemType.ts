import { FC } from "react";

/** 単一ナビゲーション */
export type NavigationSingleItem = {
  /** アイコン */
  icon?: FC;
  /** タイトル */
  title: string;
  /** 遷移先 */
  href: string;
};

/** グループナビゲーション */
export type NavigationGroupItem = {
  /** アイコン */
  icon?: FC;
  /** タイトル */
  title: string;
  /** サブメニュー */
  subs: NavigationItem[];
};

/** ナビゲーション項目 */
export type NavigationItem = NavigationSingleItem | NavigationGroupItem;
