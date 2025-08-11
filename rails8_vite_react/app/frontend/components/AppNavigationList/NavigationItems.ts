import {
  Home as HomeIcon,
  Photo as PhotoIcon,
  Settings as SettingsIcon
} from "@mui/icons-material";

import type {
  NavigationItem,
  NavigationSingleItem,
  NavigationGroupItem
} from "../NavigationList";

const createNavigationSingleItem = (item: NavigationSingleItem) => item;
const createNavigationGroupItem = (item: NavigationGroupItem) => item;

export const NAVIGATION_ITEMS: NavigationItem[] = [
  createNavigationSingleItem({
    icon: HomeIcon,
    title: "トップ",
    href: "/"
  }),
  createNavigationGroupItem({
    icon: PhotoIcon,
    title: "画像",
    subs: [
      createNavigationSingleItem({
        title: "新規作成",
        href: "/images/new"
      }),
      createNavigationSingleItem({
        title: "一覧",
        href: "/images"
      })
    ]
  }),
  createNavigationGroupItem({
    icon: SettingsIcon,
    title: "設定",
    subs: [
      createNavigationSingleItem({
        title: "プラン",
        href: "/settings/plan"
      }),
      createNavigationGroupItem({
        title: "アカウント",
        subs: [
          createNavigationSingleItem({
            title: "メアド変更",
            href: "/settings/email"
          }),
          createNavigationSingleItem({
            title: "パスワード変更",
            href: "/settings/password"
          })
        ]
      }),
      createNavigationGroupItem({
        title: "通知",
        subs: [
          createNavigationSingleItem({
            title: "デスクトップ",
            href: "/settings/notification-desktop"
          }),
          createNavigationSingleItem({
            title: "メール",
            href: "/settings/notification-email"
          })
        ]
      })
    ]
  })
];

