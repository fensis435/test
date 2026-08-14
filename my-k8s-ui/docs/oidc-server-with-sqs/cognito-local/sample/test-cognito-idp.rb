require 'aws-sdk-cognitoidentityprovider'

# 1. クライアントの初期化 (cognito-local 向け)
client = Aws::CognitoIdentityProvider::Client.new(
  region: 'ap-northeast-1',
  endpoint: 'http://127.0.0.1:9229',
  credentials: Aws::Credentials.new('dummy', 'dummy')
)

user_pool_name = 'local-user-pool'
username = 'testuser@example.com'
group_name = 'AdminGroup'

# 削除用に ID 保持用変数を宣言
user_pool_id = nil
internal_username = nil

begin
  # ----------------------------------------------------------------
  # 2. ユーザープールの作成
  # ----------------------------------------------------------------
  pool_res = client.create_user_pool({ pool_name: user_pool_name })
  user_pool_id = pool_res.user_pool.id
  puts "? ユーザープールを作成しました (ID: #{user_pool_id})"

  # ----------------------------------------------------------------
  # 3. ユーザーの作成 (AdminCreateUser)
  # ----------------------------------------------------------------
  create_user_res = client.admin_create_user({
    user_pool_id: user_pool_id,
    username: username,
    user_attributes: [
      { name: 'email', value: username },
      { name: 'email_verified', value: 'true' },
      { name: 'nickname', value: 'Taro' }
    ],
    temporary_password: 'Password123!',
    message_action: 'SUPPRESS'
  })
  internal_username = create_user_res.user.username
  puts "? ユーザーを作成しました (表示名: #{username} / 内部ID: #{internal_username})"

  # ----------------------------------------------------------------
  # 4. ユーザー詳細と属性一覧の取得 (AdminGetUser)
  # ----------------------------------------------------------------
  user_detail = client.admin_get_user({
    user_pool_id: user_pool_id,
    username: internal_username
  })

  puts "\n--- ?? ユーザー属性詳細 ---"
  puts "ユーザー名 : #{user_detail.username}"
  puts "ステータス : #{user_detail.user_status}"
  puts "属性一覧:"
  user_detail.user_attributes.each do |attr|
    puts "  - #{attr.name}: #{attr.value}"
  end

  # ----------------------------------------------------------------
  # 5. グループの作成 (CreateGroup)
  # ----------------------------------------------------------------
  client.create_group({
    user_pool_id: user_pool_id,
    group_name: group_name,
    description: '管理者権限を持つグループ'
  })
  puts "\n? グループを作成しました (#{group_name})"

  # ----------------------------------------------------------------
  # 6. ユーザーをグループに追加 (AdminAddUserToGroup)
  # ----------------------------------------------------------------
  client.admin_add_user_to_group({
    user_pool_id: user_pool_id,
    username: internal_username,
    group_name: group_name
  })
  puts "? ユーザーをグループに追加しました"

  # ----------------------------------------------------------------
  # 7. ユーザーの所属するグループ一覧を取得 (AdminListGroupsForUser)
  # ----------------------------------------------------------------
  groups_res = client.admin_list_groups_for_user({
    user_pool_id: user_pool_id,
    username: internal_username
  })

  puts "\n--- ?? ユーザーが所属するグループ一覧 ---"
  groups_res.groups.each do |group|
    puts "・グループ名 : #{group.group_name}"
    puts "  説明       : #{group.description}"
  end

ensure
  # ----------------------------------------------------------------
  # ?? クリーンアップ処理 (逆順で削除)
  # ----------------------------------------------------------------
  puts "\n--- ?? クリーンアップを開始します ---"

  if user_pool_id
    # ① ユーザーの削除
    if internal_username
      begin
        client.admin_delete_user({
          user_pool_id: user_pool_id,
          username: internal_username
        })
        puts "?? ユーザーを削除しました (内部ID: #{internal_username})"
      rescue => e
        puts "?? ユーザー削除失敗: #{e.message}"
      end
    end

    # ② グループの削除
    begin
      client.delete_group({
        user_pool_id: user_pool_id,
        group_name: group_name
      })
      puts "?? グループを削除しました (#{group_name})"
    rescue => e
      puts "?? グループ削除失敗: #{e.message}"
    end

    # ③ ユーザープールの削除
    begin
      client.delete_user_pool({
        user_pool_id: user_pool_id
      })
      puts "?? ユーザープールを削除しました (ID: #{user_pool_id})"
    rescue => e
      puts "?? ユーザープール削除失敗: #{e.message}"
    end
  end

  puts "? クリーンアップが完了しました"
end
