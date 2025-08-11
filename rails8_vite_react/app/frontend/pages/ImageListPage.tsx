import { FC } from "react";
import { Link } from "react-router-dom";

export const ImageListPage: FC = () => {
  return (
    <div>
      画像一覧ページ
      <br />
      <Link to="/images/new">画像新規作成ページ</Link>
    </div>
  );
};
