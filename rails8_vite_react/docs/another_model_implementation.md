# ============ テーブル定義 ============

# Rails 8 ポリモーフィック RolePermissions 実装コード

以下は「組織」「プロジェクト」「ユーザー」「ロール」「権限」を、ポリモーフィック関連でまとめるRailsのマイグレーションとモデル定義の例です。

---

## マイグレーション

```ruby
# db/migrate/20250801_create_organizations_users_projects.rb
class CreateOrganizationsUsersProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.timestamps
    end

    create_table :users do |t|
      t.references :organization, null: false, foreign_key: true
      t.string     :name,         null: false
      t.string     :email,        null: false, index: { unique: true }
      t.timestamps
    end

    create_table :projects do |t|
      t.references :organization, null: false, foreign_key: true
      t.string     :name,         null: false
      t.timestamps
    end
  end
end
```

```ruby
# db/migrate/20250801_create_organization_roles_and_bindings.rb
class CreateOrganizationRolesAndBindings < ActiveRecord::Migration[8.0]
  def change
    create_table :organization_roles do |t|
      t.references :organization, null: false, foreign_key: true
      t.string     :name,         null: false
      t.timestamps
    end

    create_table :user_organization_roles do |t|
      t.references :user,              null: false, foreign_key: true
      t.references :organization_role, null: false, foreign_key: true
      t.timestamps
      t.index %i[user_id organization_role_id], unique: true, name: "idx_user_org_roles"
    end
  end
end
```

```ruby
# db/migrate/20250801_create_project_roles_and_bindings.rb
class CreateProjectRolesAndBindings < ActiveRecord::Migration[8.0]
  def change
    create_table :project_roles do |t|
      t.references :project, null: false, foreign_key: true
      t.string     :name,    null: false
      t.timestamps
    end

    create_table :user_projects do |t|
      t.references :user,         null: false, foreign_key: true
      t.references :project,      null: false, foreign_key: true
      t.references :project_role, null: false, foreign_key: true
      t.timestamps
      t.index %i[user_id project_id], unique: true, name: "idx_user_project_uniqueness"
    end

```

```ruby
# db/migrate/20250801_create_permissions_and_role_permissions.rb
class CreatePermissionsAndRolePermissions < ActiveRecord::Migration[8.0]
  def change
    create_table :permissions do |t|
      t.string :name,        null: false, index: { unique: true }
      t.text   :description
      t.timestamps
    end

    create_table :role_permissions do |t|
      t.references :permission, null: false, foreign_key: true
      t.references :role,       polymorphic: true, null: false, index: { name: "idx_role_permissions_on_role" }
      t.timestamps
      t.index %i[role_type role_id permission_id], unique: true, name: "idx_polymorphic_role_perms"
    end
  end
end
```

---

# ============ モデル定義 ============

## モデル定義

### app/models/organization.rb

```ruby
class Organization < ApplicationRecord
  has_many :users,    dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :organization_roles, dependent: :destroy
end
```

### app/models/user.rb

```ruby
class User < ApplicationRecord
  belongs_to :organization

  has_many :user_projects, dependent: :destroy
  has_many :projects, through: :user_projects
  has_many :project_roles, through: :user_projects

  has_many :user_organization_roles, dependent: :destroy
  has_many :organization_roles, through: :user_organization_roles

  validates :name,  presence: true
  validates :email, presence: true, uniqueness: true
end
```

### app/models/project.rb

````ruby
class Project < ApplicationRecord
  belongs_to :organization

  has_many :user_projects, dependent: :destroy
  has_many :users, through: :user_projects

  has_many :project_roles, dependent: :destroy

  validates :name, presence: true
end


### app/models/organization_role.rb

```ruby
class OrganizationRole < ApplicationRecord
  belongs_to :organization

  has_many :user_organization_roles, dependent: :destroy
  has_many :users, through: :user_organization_roles

  has_many :role_permissions, as: :role, dependent: :destroy
  has_many :permissions, through: :role_permissions

  validates :name, presence: true, uniqueness: { scope: :organization_id }
end
````

### app/models/project_role.rb

```ruby
class ProjectRole < ApplicationRecord
  belongs_to :project

  has_many :user_projects, dependent: :nullify
  has_many :users, through: :user_projects

  has_many :role_permissions, as: :role, dependent: :destroy
  has_many :permissions, through: :role_permissions

  validates :name, presence: true, uniqueness: { scope: :project_id }
end
```

### app/models/user_organization_role.rb

```ruby
class UserOrganizationRole < ApplicationRecord
  belongs_to :user
  belongs_to :organization_role

  validate :user_belongs_to_same_organization

  private

  def user_belongs_to_same_organization
    return if user.organization_id == organization_role.organization_id

    errors.add(:user, "must be in the same organization as the role")
  end
end
```

### app/models/user_project.rb

```ruby
class UserProject < ApplicationRecord
  belongs_to :user
  belongs_to :project
  belongs_to :project_role

  validate :same_organization_for_user_and_project
  validate :project_role_belongs_to_project

  private

  # ユーザーとプロジェクトは同一組織に属していること
  def same_organization_for_user_and_project
    return if user.organization_id == project.organization_id

    errors.add(:user, "must belong to the same organization as the project")
  end

  # プロジェクトロールはこのプロジェクトに紐づくこと
  def project_role_belongs_to_project
    return if project_role.project_id == project_id

    errors.add(:project_role, "must belong to the same project")
  end
end
```

### app/models/permission.rb

````ruby
class Permission < ApplicationRecord
  has_many :role_permissions, dependent: :destroy
  has_many :organization_roles, through: :role_permissions, source: :role, source_type: "OrganizationRole"
  has_many :project_roles,      through: :role_permissions, source: :role, source_type: "ProjectRole"

  validates :name, presence: true, uniqueness: true
end

### app/models/role_permission.rb

```ruby
class RolePermission < ApplicationRecord
  belongs_to :permission
  belongs_to :role, polymorphic: true

  validates :permission_id, uniqueness: { scope: %i[role_type role_id] }
end
````

---

## 権限チェック例

```ruby
class PermissionChecker
  def initialize(user:, resource:, action:)
    @user     = user
    @resource = resource    # Organization or Project
    @action   = action.to_s
  end

  def allowed?
    case @resource
    when Organization
      @user.organization_roles
           .joins(:permissions)
           .exists?(permissions: { name: @action })
    when Project
      @user.project_roles
           .joins(:permissions)
           .exists?(permissions: { name: @action })
    else
      false
    end
  end
end
```

---

以上で、組織／プロジェクト双方のロールおよび権限をポリモーフィックに一元管理するRails 8コードが揃いました。必要に応じてシードデータやキャッシュ層を追加するとさらに運用しやすくなります。

---

# ============ テスト用シードデータ ============

# テスト用シードデータ (db/seeds.rb)

```ruby
# Destroy existing data in the correct order
RolePermission.destroy_all
UserProject.destroy_all
UserOrganizationRole.destroy_all
Permission.destroy_all
ProjectRole.destroy_all
OrganizationRole.destroy_all
Project.destroy_all
User.destroy_all
Organization.destroy_all

# Create Organizations
org_alpha = Organization.create!(name: 'Alpha Corp')
org_beta  = Organization.create!(name: 'Beta Ltd')

# Create Users
alice = org_alpha.users.create!(name: 'Alice', email: 'alice@alpha.example.com')
bob   = org_alpha.users.create!(name: 'Bob',   email: 'bob@alpha.example.com')
carol = org_beta.users.create!(name: 'Carol', email: 'carol@beta.example.com')
dave  = org_beta.users.create!(name: 'Dave',  email: 'dave@beta.example.com')

# Create OrganizationRoles
alpha_admin  = org_alpha.organization_roles.create!(name: 'Org Admin')
alpha_member = org_alpha.organization_roles.create!(name: 'Member')
beta_admin   = org_beta.organization_roles.create!(name: 'Org Admin')
beta_member  = org_beta.organization_roles.create!(name: 'Member')

# Assign OrganizationRoles to Users
UserOrganizationRole.create!(user: alice, organization_role: alpha_admin)
UserOrganizationRole.create!(user: bob,   organization_role: alpha_member)
UserOrganizationRole.create!(user: carol, organization_role: beta_admin)
UserOrganizationRole.create!(user: dave,  organization_role: beta_member)

# Create Projects
proj_x = org_alpha.projects.create!(name: 'Project X')
proj_y = org_alpha.projects.create!(name: 'Project Y')
proj_z = org_beta.projects.create!(name: 'Project Z')

# Create ProjectRoles
x_manager       = proj_x.project_roles.create!(name: 'Manager')
x_contributor   = proj_x.project_roles.create!(name: 'Contributor')
y_manager       = proj_y.project_roles.create!(name: 'Manager')
z_contributor   = proj_z.project_roles.create!(name: 'Contributor')

# Assign Users to Projects with Roles
UserProject.create!(user: alice, project: proj_x, project_role: x_manager)
UserProject.create!(user: bob,   project: proj_x, project_role: x_contributor)
UserProject.create!(user: alice, project: proj_y, project_role: y_manager)
UserProject.create!(user: carol, project: proj_z, project_role: z_contributor)

# Create Permissions
perm_read   = Permission.create!(name: 'read',   description: 'Read access')
perm_write  = Permission.create!(name: 'write',  description: 'Write access')
perm_delete = Permission.create!(name: 'delete', description: 'Delete access')

# Grant Permissions to OrganizationRoles
RolePermission.create!(role: alpha_admin,  permission: perm_read)
RolePermission.create!(role: alpha_admin,  permission: perm_write)
RolePermission.create!(role: alpha_admin,  permission: perm_delete)
RolePermission.create!(role: alpha_member, permission: perm_read)

RolePermission.create!(role: beta_admin,   permission: perm_read)
RolePermission.create!(role: beta_admin,   permission: perm_write)
RolePermission.create!(role: beta_member,  permission: perm_read)

# Grant Permissions to ProjectRoles
RolePermission.create!(role: x_manager,     permission: perm_read)
RolePermission.create!(role: x_manager,     permission: perm_write)
RolePermission.create!(role: x_contributor, permission: perm_read)
RolePermission.create!(role: y_manager,     permission: perm_read)
RolePermission.create!(role: y_manager,     permission: perm_write)
RolePermission.create!(role: z_contributor, permission: perm_read)

puts "Seed data created successfully!"
```

---

# ============ REST-API実装 ============

# REST-API ルーティング設定

```ruby
# config/routes.rb
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :organizations do
        resources :users,                  only: %i[index create]
        resources :organization_roles,     only: %i[index create]
      end

      resources :users, only: %i[show update destroy] do
        resources :user_organization_roles, only: %i[index create destroy]
      end

      resources :projects, only: %i[index show create update destroy] do
        resources :project_roles,      only: %i[index create]
      end

      resources :project_roles,        only: %i[show update destroy] do
        resources :role_permissions,   only: %i[index create destroy]
      end

      resources :permissions, only: %i[index show create update destroy]

      resources :user_projects, only: %i[index create show update destroy]
      resources :role_permissions, only: %i[show update destroy]
    end
  end
end
```

---

## ApplicationController（共通エラーハンドリング）

```ruby
# app/controllers/api/v1/application_controller.rb
module Api
  module V1
    class ApplicationController < ActionController::API
      rescue_from ActiveRecord::RecordNotFound do |e|
        render json: { error: e.message }, status: :not_found
      end

      rescue_from ActiveRecord::RecordInvalid do |e|
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end
end
```

---

## OrganizationsController

```ruby
# app/controllers/api/v1/organizations_controller.rb
module Api
  module V1
    class OrganizationsController < ApplicationController
      def index
        render json: Organization.all
      end

      def show
        render json: organization
      end

      def create
        org = Organization.create!(organization_params)
        render json: org, status: :created
      end

      def update
        organization.update!(organization_params)
        render json: organization
      end

      def destroy
        organization.destroy
        head :no_content
      end

      private

      def organization
        @organization ||= Organization.find(params[:id])
      end

      def organization_params
        params.require(:organization).permit(:name)
      end
    end
  end
end
```

---

## UsersController

```ruby
# app/controllers/api/v1/users_controller.rb
module Api
  module V1
    class UsersController < ApplicationController
      before_action :set_organization, only: %i[index create]
      before_action :set_user,         only: %i[show update destroy]

      def index
        render json: @organization.users
      end

      def show
        render json: @user
      end

      def create
        user = @organization.users.create!(user_params)
        render json: user, status: :created
      end

      def update
        @user.update!(user_params)
        render json: @user
      end

      def destroy
        @user.destroy
        head :no_content
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      end

      def set_user
        @user = User.find(params[:id])
      end

      def user_params
        params.require(:user).permit(:name, :email)
      end
    end
  end
end
```

---

## ProjectsController

```ruby
# app/controllers/api/v1/projects_controller.rb
module Api
  module V1
    class ProjectsController < ApplicationController
      def index
        render json: Project.all
      end

      def show
        render json: project
      end

      def create
        proj = Organization.find(params[:project][:organization_id])
                           .projects.create!(project_params)
        render json: proj, status: :created
      end

      def update
        project.update!(project_params)
        render json: project
      end

      def destroy
        project.destroy
        head :no_content
      end

      private

      def project
        @project ||= Project.find(params[:id])
      end

      def project_params
        params.require(:project).permit(:name)
      end
    end
  end
end
```

---

## ProjectRolesController

```ruby
# app/controllers/api/v1/project_roles_controller.rb
module Api
  module V1
    class ProjectRolesController < ApplicationController
      before_action :set_project,      only: %i[index create]
      before_action :set_project_role, only: %i[show update destroy]

      def index
        render json: @project.project_roles
      end

      def show
        render json: @project_role
      end

      def create
        role = @project.project_roles.create!(role_params)
        render json: role, status: :created
      end

      def update
        @project_role.update!(role_params)
        render json: @project_role
      end

      def destroy
        @project_role.destroy
        head :no_content
      end

      private

      def set_project
        @project = Project.find(params[:project_id])
      end

      def set_project_role
        @project_role = ProjectRole.find(params[:id])
      end

      def role_params
        params.require(:project_role).permit(:name)
      end
    end
  end
end
```

---

## UserProjectsController

```ruby
# app/controllers/api/v1/user_projects_controller.rb
module Api
  module V1
    class UserProjectsController < ApplicationController
      def index
        render json: UserProject.all
      end

      def show
        render json: user_project
      end

      def create
        up = UserProject.create!(user_project_params)
        render json: up, status: :created
      end

      def update
        user_project.update!(user_project_params)
        render json: user_project
      end

      def destroy
        user_project.destroy
        head :no_content
      end

      private

      def user_project
        @user_project ||= UserProject.find(params[:id])
      end

      def user_project_params
        params.require(:user_project).permit(:user_id, :project_id, :project_role_id)
      end
    end
  end
end
```

---

## PermissionsController

```ruby
# app/controllers/api/v1/permissions_controller.rb
module Api
  module V1
    class PermissionsController < ApplicationController
      def index
        render json: Permission.all
      end

      def show
        render json: permission
      end

      def create
        p = Permission.create!(permission_params)
        render json: p, status: :created
      end

      def update
        permission.update!(permission_params)
        render json: permission
      end

      def destroy
        permission.destroy
        head :no_content
      end

      private

      def permission
        @permission ||= Permission.find(params[:id])
      end

      def permission_params
        params.require(:permission).permit(:name, :description)
      end
    end
  end
end
```

---

## RolePermissionsController

```ruby
# app/controllers/api/v1/role_permissions_controller.rb
module Api
  module V1
    class RolePermissionsController < ApplicationController
      before_action :set_role_permission, only: %i[show destroy]

      def index
        if params[:project_role_id]
          render json: ProjectRole.find(params[:project_role_id]).role_permissions
        elsif params[:organization_role_id]
          render json: OrganizationRole.find(params[:organization_role_id]).role_permissions
        else
          render json: RolePermission.all
        end
      end

      def show
        render json: @role_permission
      end

      def create
        rp = RolePermission.create!(role_permission_params)
        render json: rp, status: :created
      end

      def destroy
        @role_permission.destroy
        head :no_content
      end

      private

      def set_role_permission
        @role_permission ||= RolePermission.find(params[:id])
      end

      def role_permission_params
        params.require(:role_permission).permit(:role_type, :role_id, :permission_id)
      end
    end
  end
end
```

---

# ============ REST-API改良 ============
以下のように、ユーザーごとの「組織ロール＋権限」と「プロジェクトロール＋権限」を一括で取得・更新できる専用エンドポイントを追加すると、フロント側から発行するRESTコールをまとめられます。

---

## 1. ルーティング追加

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :users, only: [] do
      # 単一画面向けの一括取得／更新
      resource :roles_permissions,
               only: %i[show update],
               controller: 'users_roles_permissions'
    end
  end
end
```

---

## 2. コントローラ実装

```ruby
# app/controllers/api/v1/users_roles_permissions_controller.rb
module Api
  module V1
    class UsersRolesPermissionsController < ApplicationController
      before_action :set_user

      # GET   /api/v1/users/:user_id/roles_permissions
      def show
        render json: payload
      end

      # PUT   /api/v1/users/:user_id/roles_permissions
      def update
        User.transaction do
          assign_organization_role!
          assign_project_roles!
        end

        render json: payload
      end

      private

      def set_user
        @user = User.find(params[:user_id])
      end

      # レスポンス用ペイロード
      def payload
        {
          organization: {
            current_role_id: @user.organization_roles.pluck(:id).first,
            granted_permission_ids: @user.organization_roles
                                       .joins(:permissions)
                                       .pluck('permissions.id')
          },
          projects: @user.user_projects.includes(:project, :project_role).map { |up|
            {
              project_id:      up.project_id,
              current_role_id: up.project_role_id,
              granted_permission_ids: up.project_role.permissions.pluck(:id)
            }
          }
        }
      end

      # 組織ロールの一括更新
      def assign_organization_role!
        # 受け取るパラメータ例:
        # { organization_role_id: 2, granted_permission_ids: [1,2,3] }
        org_role_id = rp_params[:organization_role_id]
        perm_ids    = rp_params[:granted_permission_ids] || []

        # 1) 組織ロールを入れ替え
        @user.user_organization_roles.destroy_all
        @user.user_organization_roles.create!(organization_role_id: org_role_id)

        # 2) 権限（RolePermission）をリセット
        RolePermission
          .where(role_type: 'OrganizationRole', role_id: org_role_id)
          .where.not(permission_id: perm_ids)
          .delete_all

        perm_ids.each do |pid|
          RolePermission.find_or_create_by!(
            role_type:    'OrganizationRole',
            role_id:      org_role_id,
            permission_id: pid
          )
        end
      end

      # プロジェクトロール＋権限の一括更新
      def assign_project_roles!
        # 受け取るパラメータ例:
        # { projects: [
        #     { project_id: 1, project_role_id: 3, granted_permission_ids: [1,2] },
        #     { project_id: 2, project_role_id: 4, granted_permission_ids: [1] }
        #   ]
        # }
        up_params = rp_params[:projects] || []

        # 既存の結びつきを消してから再作成
        @user.user_projects.destroy_all

        up_params.each do |h|
          project_id    = h[:project_id]
          role_id       = h[:project_role_id]
          perm_ids      = h[:granted_permission_ids] || []

          # 1) user_projects
          @user.user_projects.create!(
            project_id:       project_id,
            project_role_id:  role_id
          )

          # 2) role_permissions の調整
          RolePermission
            .where(role_type: 'ProjectRole', role_id: role_id)
            .where.not(permission_id: perm_ids)
            .delete_all

          perm_ids.each do |pid|
            RolePermission.find_or_create_by!(
              role_type:    'ProjectRole',
              role_id:      role_id,
              permission_id: pid
            )
          end
        end
      end

      def rp_params
        params.require(:roles_permissions).permit(
          :organization_role_id,
          granted_permission_ids: [],
          projects: [
            :project_id,
            :project_role_id,
            { granted_permission_ids: [] }
          ]
        )
      end
    end
  end
end
```

---

## 3. フロントとのやりとり例

### 一括取得

GET /api/v1/users/12/roles_permissions

```json
{
  "organization": {
    "current_role_id": 2,
    "granted_permission_ids": [1, 2, 5]
  },
  "projects": [
    {
      "project_id": 7,
      "current_role_id": 3,
      "granted_permission_ids": [1, 3]
    },
    {
      "project_id": 8,
      "current_role_id": 4,
      "granted_permission_ids": [1]
    }
  ]
}
```

### 一括更新

PUT /api/v1/users/12/roles_permissions  
Content-Type: application/json  
Body:

```json
{
  "roles_permissions": {
    "organization_role_id": 3,
    "granted_permission_ids": [1, 4],
    "projects": [
      {
        "project_id": 7,
        "project_role_id": 5,
        "granted_permission_ids": [1, 2]
      },
      { "project_id": 8, "project_role_id": 6, "granted_permission_ids": [1] }
    ]
  }
}
```

---

# JSON:API 仕様に準拠した統一レスポンス設計（ActiveModelSerializers）

---

## 1. ActiveModelSerializers の設定

```ruby
# Gemfile
gem 'active_model_serializers', '~> 0.10.0'
```

```ruby
# config/initializers/active_model_serializers.rb
ActiveModelSerializers.config.adapter = :json_api
ActiveModelSerializers.config.key_transform = :unaltered
```

---

## 2. シリアライザー定義例

### app/serializers/user_roles_permissions_serializer.rb

```ruby
class UserRolesPermissionsSerializer
  include JSONAPI::Serializer  # AMS v0.10のjson_apiアダプターを想定

  set_type :roles_permissions

  attribute :organization do |object, params|
    {
      id:         object[:organization][:current_role_id],
      permission_ids: object[:organization][:granted_permission_ids]
    }
  end

  attribute :projects do |object, params|
    object[:projects].map do |pr|
      {
        project_id:       pr[:project_id],
        project_role_id:  pr[:current_role_id],
        permission_ids:   pr[:granted_permission_ids]
      }
    end
  end
end
```

### app/serializers/organization_role_serializer.rb

```ruby
class OrganizationRoleSerializer < ActiveModel::Serializer
  type 'organization_roles'

  attributes :id, :name

  has_many :permissions,
           serializer: PermissionSerializer
end
```

### app/serializers/project_role_serializer.rb

```ruby
class ProjectRoleSerializer < ActiveModel::Serializer
  type 'project_roles'

  attributes :id, :name, :project_id

  has_many :permissions,
           serializer: PermissionSerializer
end
```

### app/serializers/permission_serializer.rb

```ruby
class PermissionSerializer < ActiveModel::Serializer
  type 'permissions'

  attributes :id, :name, :description
end
```

---

## 3. コントローラへの組み込み例

```ruby
# app/controllers/api/v1/users_roles_permissions_controller.rb
module Api::V1
  class UsersRolesPermissionsController < ApplicationController
    def show
      render json: UserRolesPermissionsSerializer.new(payload).serializable_hash
    end

    def update
      # ...更新処理...
      render json: UserRolesPermissionsSerializer.new(payload).serializable_hash
    end
  end
end
```

---

# ユーザー視点のUIコンポーネント設計：マトリクス型チェックボックス

---

## 1. 画面構成イメージ

```
---------------------------------------------------------
| 組織ロール: [ドロップダウン]                           |
| 権限マトリクス                                         |
|   ┌───────────────┬─────────┬─────────┐               |
|   │               │ read    │ write   │ delete │     |
|   ├───────────────┼─────────┼─────────┼─────────┤     |
|   │ Org Admin     │ [x]     │ [x]     │ [x]    │     |
|   ├───────────────┼─────────┼─────────┼─────────┤     |
|   │ Member        │ [x]     │ [ ]     │ [ ]    │     |
|   └───────────────┴─────────┴─────────┴─────────┘     |
|                                                       |
| プロジェクト別設定                                    |
|   ┌────────┬───────────────┬─────────┬─────────┐      |
|   │ Project│ Role          │ read    │ write   │     |
|   ├────────┼───────────────┼─────────┼─────────┤     |
|   │ X      │ [ドロップダウン] │ [x]     │ [ ]     │     |
|   ├────────┼───────────────┼─────────┼─────────┤     |
|   │ Y      │ [ドロップダウン] │ [x]     │ [x]     │     |
|   └────────┴───────────────┴─────────┴─────────┘     |
---------------------------------------------------------
[保存] [キャンセル]
```

---

## 2. Reactコンポーネント例

```jsx
import React, { useState, useEffect } from 'react';
import axios from 'axios';

// props.userId を受けて一括取得・更新を行う
export function RolesPermissionsEditor({ userId }) {
  const [data, setData] = useState(null);

  useEffect(() => {
    axios
      .get(`/api/v1/users/${userId}/roles_permissions`)
      .then((res) => setData(res.data));
  }, [userId]);

  if (!data) return <div>Loading...</div>;

  const handleOrgRoleChange = (e) => {
    setData({
      ...data,
      organization: {
        ...data.organization,
        current_role_id: parseInt(e.target.value, 10)
      }
    });
  };

  const handleOrgPermToggle = (permId) => {
    const perms = new Set(data.organization.permission_ids);
    perms.has(permId) ? perms.delete(permId) : perms.add(permId);
    setData({
      ...data,
      organization: {
        ...data.organization,
        permission_ids: Array.from(perms)
      }
    });
  };

  const handleProjectRoleChange = (projectIndex, roleId) => {
    const projects = [...data.projects];
    projects[projectIndex].project_role_id = roleId;
    setData({ ...data, projects });
  };

  const handleProjectPermToggle = (projectIndex, permId) => {
    const projects = [...data.projects];
    const permSet = new Set(projects[projectIndex].permission_ids);
    permSet.has(permId) ? permSet.delete(permId) : permSet.add(permId);
    projects[projectIndex].permission_ids = Array.from(permSet);
    setData({ ...data, projects });
  };

  const save = () => {
    axios
      .put(`/api/v1/users/${userId}/roles_permissions`, {
        roles_permissions: data
      })
      .then((res) => setData(res.data));
  };

  return (
    <div>
      {/* 組織ロール＆権限 */}
      <section>
        <h2>組織ロールと権限</h2>
        <select
          value={data.organization.current_role_id}
          onChange={handleOrgRoleChange}
        >
          {/* options は事前にフェッチしておく */}
        </select>
        <table>
          <thead>
            <tr>
              <th>権限</th>
              {permissionList.map((p) => (
                <th key={p.id}>{p.name}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            <tr>
              <td></td>
              {permissionList.map((p) => (
                <td key={p.id}>
                  <input
                    type='checkbox'
                    checked={data.organization.permission_ids.includes(p.id)}
                    onChange={() => handleOrgPermToggle(p.id)}
                    aria-label={`Org perm ${p.name}`}
                  />
                </td>
              ))}
            </tr>
          </tbody>
        </table>
      </section>

      {/* プロジェクト別 */}
      <section>
        <h2>プロジェクト別ロールと権限</h2>
        <table>
          <thead>
            <tr>
              <th>プロジェクト</th>
              <th>ロール</th>
              {permissionList.map((p) => (
                <th key={p.id}>{p.name}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {data.projects.map((pr, idx) => (
              <tr key={pr.project_id}>
                <td>{projectMap[pr.project_id].name}</td>
                <td>
                  <select
                    value={pr.project_role_id}
                    onChange={(e) =>
                      handleProjectRoleChange(idx, parseInt(e.target.value, 10))
                    }
                  >
                    {projectRoleMap[pr.project_id].map((r) => (
                      <option key={r.id} value={r.id}>
                        {r.name}
                      </option>
                    ))}
                  </select>
                </td>
                {permissionList.map((p) => (
                  <td key={p.id}>
                    <input
                      type='checkbox'
                      checked={pr.permission_ids.includes(p.id)}
                      onChange={() => handleProjectPermToggle(idx, p.id)}
                      aria-label={`Project ${pr.project_id} perm ${p.name}`}
                    />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <button onClick={save}>保存</button>
    </div>
  );
}
```

---

## 3. UX・アクセシビリティのポイント

- キーボード操作：Tab/Space でチェックボックスにフォーカス＆切り替え
- ラベル付与：`aria-label` で行・列を明示
- 色分け：許可中のセルを薄いグリーン、未許可は薄いグレー背景にすると視認性アップ
- スマホ対応：テーブルを横スクロール可能にする、もしくはカード型に変換
- バリデーション：必須項目（ロール未選択など）を保存前にインラインでエラーメッセージ表示

---

これにより、フロントエンドからは1つの JSON:API 準拠エンドポイントだけを呼び出し、マトリクス型UIで組織とプロジェクト両方のロール／権限を一括操作できるようになります。

---

# ============ GUI実装(React+MUI) ============

---

# RolesPermissionsEditor コンポーネント実装 (Vite + React + MUI)

## 1. レイアウトとルーティング

アプリケーション全体のレイアウトは、すでに MUI のドロワーとアプリバーをラップする `PersistentDrawerLeft` コンポーネントを使っている想定です。ここでは React Router でメニュー選択後に真ん中に表示する方法を示します。

```jsx
// src/App.jsx
import React from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import PersistentDrawerLeft from './layout/PersistentDrawerLeft';
import Dashboard from './pages/Dashboard';
import RolesPermissionsPage from './pages/RolesPermissionsPage';

export default function App() {
  return (
    <BrowserRouter>
      <PersistentDrawerLeft>
        <Routes>
          <Route path='/' element={<Dashboard />} />
          <Route
            path='/users/:userId/roles-permissions'
            element={<RolesPermissionsPage />}
          />
        </Routes>
      </PersistentDrawerLeft>
    </BrowserRouter>
  );
}
```

- `PersistentDrawerLeft` の `children` 部分に、選択されたメニューに応じたコンポーネントをレンダーします。
- `/users/:userId/roles-permissions` へ遷移すると、中央エリアに `RolesPermissionsPage` が表示されます。

---

## 2. ページコンポーネント

```jsx
// src/pages/RolesPermissionsPage.jsx
import React from 'react';
import { useParams } from 'react-router-dom';
import { Box, Typography } from '@mui/material';
import RolesPermissionsEditor from '../components/RolesPermissionsEditor';

export default function RolesPermissionsPage() {
  const { userId } = useParams();

  return (
    <Box sx={{ p: 3 }}>
      <Typography variant='h5' gutterBottom>
        ユーザー権限設定
      </Typography>
      <RolesPermissionsEditor userId={userId} />
    </Box>
  );
}
```

- `userId` を URL パラメータから取得し、エディターコンポーネントに渡します。

---

## 3. RolesPermissionsEditor コンポーネント

```jsx
// src/components/RolesPermissionsEditor.jsx
import React, { useEffect, useState } from 'react';
import axios from 'axios';
import {
  Box,
  Typography,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  Table,
  TableHead,
  TableRow,
  TableCell,
  TableBody,
  Checkbox,
  Button,
  CircularProgress
} from '@mui/material';

export default function RolesPermissionsEditor({ userId }) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [orgRoles, setOrgRoles] = useState([]);
  const [projectRolesMap, setProjectRolesMap] = useState({});
  const [permissions, setPermissions] = useState([]);

  useEffect(() => {
    async function fetchAll() {
      try {
        const [{ data: rp }, { data: permsRes }] = await Promise.all([
          axios.get(`/api/v1/users/${userId}/roles_permissions`),
          axios.get('/api/v1/permissions')
        ]);
        setData(rp);
        setPermissions(permsRes.data);
        // 組織ロール一覧を取得
        const orgId = rp.organization.organization_id;
        const orgRolesRes = await axios.get(
          `/api/v1/organizations/${orgId}/organization_roles`
        );
        setOrgRoles(orgRolesRes.data.data);
        // 各プロジェクトのロール一覧を取得
        const promises = rp.projects.map((pr) =>
          axios
            .get(`/api/v1/projects/${pr.project_id}/project_roles`)
            .then((res) => [pr.project_id, res.data.data])
        );
        const entries = await Promise.all(promises);
        setProjectRolesMap(Object.fromEntries(entries));
      } catch (e) {
        console.error(e);
      } finally {
        setLoading(false);
      }
    }
    fetchAll();
  }, [userId]);

  if (loading) return <CircularProgress />;

  const toggleSet = (arr, id) => {
    const s = new Set(arr);
    s.has(id) ? s.delete(id) : s.add(id);
    return Array.from(s);
  };

  const handleOrgRoleChange = (e) =>
    setData({
      ...data,
      organization: {
        ...data.organization,
        organization_role_id: +e.target.value
      }
    });

  const handleOrgPermToggle = (permId) =>
    setData({
      ...data,
      organization: {
        ...data.organization,
        granted_permission_ids: toggleSet(
          data.organization.granted_permission_ids,
          permId
        )
      }
    });

  const handleProjectRoleChange = (i, roleId) => {
    const projects = [...data.projects];
    projects[i].project_role_id = +roleId;
    setData({ ...data, projects });
  };

  const handleProjectPermToggle = (i, permId) => {
    const projects = [...data.projects];
    projects[i].granted_permission_ids = toggleSet(
      projects[i].granted_permission_ids,
      permId
    );
    setData({ ...data, projects });
  };

  const save = async () => {
    setLoading(true);
    try {
      const res = await axios.put(`/api/v1/users/${userId}/roles_permissions`, {
        roles_permissions: data
      });
      setData(res.data);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Box>
      {/* 組織ロールと権限 */}
      <Box mb={4}>
        <Typography variant='h6'>組織ロールと権限</Typography>
        <FormControl sx={{ minWidth: 240, mt: 2 }}>
          <InputLabel>組織ロール</InputLabel>
          <Select
            value={data.organization.organization_role_id}
            label='組織ロール'
            onChange={handleOrgRoleChange}
          >
            {orgRoles.map((r) => (
              <MenuItem key={r.id} value={r.id}>
                {r.attributes.name}
              </MenuItem>
            ))}
          </Select>
        </FormControl>
        <Table sx={{ mt: 2 }}>
          <TableHead>
            <TableRow>
              <TableCell>権限</TableCell>
              {permissions.map((p) => (
                <TableCell key={p.id} align='center'>
                  {p.name}
                </TableCell>
              ))}
            </TableRow>
          </TableHead>
          <TableBody>
            <TableRow>
              <TableCell></TableCell>
              {permissions.map((p) => (
                <TableCell key={p.id} align='center'>
                  <Checkbox
                    checked={data.organization.granted_permission_ids.includes(
                      p.id
                    )}
                    onChange={() => handleOrgPermToggle(p.id)}
                  />
                </TableCell>
              ))}
            </TableRow>
          </TableBody>
        </Table>
      </Box>

      {/* プロジェクト別設定 */}
      <Box mb={4}>
        <Typography variant='h6'>プロジェクト別設定</Typography>
        {data.projects.map((pr, i) => (
          <Box key={pr.project_id} mb={3}>
            <Typography gutterBottom>プロジェクト {pr.project_id}</Typography>
            <FormControl sx={{ minWidth: 240 }}>
              <InputLabel>プロジェクトロール</InputLabel>
              <Select
                value={pr.project_role_id}
                label='プロジェクトロール'
                onChange={(e) => handleProjectRoleChange(i, e.target.value)}
              >
                {(projectRolesMap[pr.project_id] || []).map((r) => (
                  <MenuItem key={r.id} value={r.id}>
                    {r.attributes.name}
                  </MenuItem>
                ))}
              </Select>
            </FormControl>
            <Table sx={{ mt: 2 }}>
              <TableHead>
                <TableRow>
                  <TableCell>権限</TableCell>
                  {permissions.map((p) => (
                    <TableCell key={p.id} align='center'>
                      {p.name}
                    </TableCell>
                  ))}
                </TableRow>
              </TableHead>
              <TableBody>
                <TableRow>
                  <TableCell></TableCell>
                  {permissions.map((p) => (
                    <TableCell key={p.id} align='center'>
                      <Checkbox
                        checked={pr.granted_permission_ids.includes(p.id)}
                        onChange={() => handleProjectPermToggle(i, p.id)}
                      />
                    </TableCell>
                  ))}
                </TableRow>
              </TableBody>
            </Table>
          </Box>
        ))}
      </Box>

      <Button variant='contained' onClick={save} disabled={loading}>
        保存
      </Button>
    </Box>
  );
}
```

---

### ポイント

- MUI の `Box` を使って余白を制御
- `FormControl`＋`Select` でロール選択
- `Table` と `Checkbox` で権限マトリクスを表現
- `CircularProgress` でロード中インジケーター
- API 呼び出しは `axios` でまとめて行い、データ取得→マスタ取得→保存をシンプルに

---

これで、Vite＋React＋MUI 環境下で、ドロワー／アプリバーの下に“RolesPermissionsEditor”を真ん中に表示し、組織とプロジェクト両方のロール／権限を一括編集できるUIが完成します。

---

# ============ GUIインライン編集 ============

# 部分編集可能な一覧＋行単位編集UI（Vite＋React＋MUI）

以下は「組織ロール」「プロジェクトロール＋権限」を

- デフォルトはテキスト表示の一覧
- 行ごとの編集ボタンで、その行だけSelect＋Checkboxに切り替え
- 行単位で保存／キャンセル

を実現するコンポーネント例です。

---

## 1. RolesPermissionsEditor.jsx

```jsx
import React, { useEffect, useState } from 'react';
import axios from 'axios';
import {
  Box,
  Button,
  Checkbox,
  CircularProgress,
  FormControl,
  IconButton,
  InputLabel,
  MenuItem,
  Select,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  Typography
} from '@mui/material';
import EditIcon from '@mui/icons-material/Edit';
import SaveIcon from '@mui/icons-material/Save';
import CloseIcon from '@mui/icons-material/Close';

export default function RolesPermissionsEditor({ userId }) {
  const [data, setData] = useState(null); // フルペイロード
  const [origData, setOrigData] = useState(null); // キャンセル用オリジナル
  const [orgRoles, setOrgRoles] = useState([]); // マスタ：組織ロール
  const [projectRolesMap, setProjectRolesMap] = useState({}); // マスタ：プロジェクトごとロール
  const [permissions, setPermissions] = useState([]); // マスタ：権限
  const [loading, setLoading] = useState(true);

  // 編集フラグ
  const [editingOrg, setEditingOrg] = useState(false);
  const [editingProjIds, setEditingProjIds] = useState(new Set());

  // 初回データ取得
  useEffect(() => {
    async function fetchAll() {
      try {
        const [{ data: rp }, { data: permsRes }] = await Promise.all([
          axios.get(`/api/v1/users/${userId}/roles_permissions`),
          axios.get('/api/v1/permissions')
        ]);
        setData(rp);
        setOrigData(JSON.parse(JSON.stringify(rp)));
        setPermissions(permsRes.data.data);

        // 組織ロール
        const orgId = rp.organization.organization_id;
        const { data: orgRolesRes } = await axios.get(
          `/api/v1/organizations/${orgId}/organization_roles`
        );
        setOrgRoles(orgRolesRes.data.data);

        // 各プロジェクトのロール
        const entries = await Promise.all(
          rp.projects.map((pr) =>
            axios
              .get(`/api/v1/projects/${pr.project_id}/project_roles`)
              .then((res) => [pr.project_id, res.data.data])
          )
        );
        setProjectRolesMap(Object.fromEntries(entries));
      } catch (err) {
        console.error(err);
      } finally {
        setLoading(false);
      }
    }
    fetchAll();
  }, [userId]);

  if (loading || !data) return <CircularProgress />;

  // ユーティリティ：権限配列の追加?削除
  const toggleSet = (arr, id) => {
    const s = new Set(arr);
    s.has(id) ? s.delete(id) : s.add(id);
    return Array.from(s);
  };

  // 行単位Save／Cancel
  const saveOrg = async () => {
    setLoading(true);
    try {
      const payload = {
        organization_role_id: data.organization.organization_role_id,
        granted_permission_ids: data.organization.granted_permission_ids,
        projects: data.projects.map((pr) => ({
          project_id: pr.project_id,
          project_role_id: pr.project_role_id,
          granted_permission_ids: pr.granted_permission_ids
        }))
      };
      const res = await axios.put(`/api/v1/users/${userId}/roles_permissions`, {
        roles_permissions: payload
      });
      setData(res.data);
      setOrigData(JSON.parse(JSON.stringify(res.data)));
      setEditingOrg(false);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  const cancelOrg = () => {
    setData(JSON.parse(JSON.stringify(origData)));
    setEditingOrg(false);
  };

  const saveProj = async (projIndex) => {
    setLoading(true);
    try {
      // 編集中プロジェクトだけペイロードに反映
      const updPayload = {
        organization_role_id: data.organization.organization_role_id,
        granted_permission_ids: data.organization.granted_permission_ids,
        projects: data.projects.map((pr, idx) => {
          if (idx === projIndex) {
            return {
              project_id: pr.project_id,
              project_role_id: pr.project_role_id,
              granted_permission_ids: pr.granted_permission_ids
            };
          }
          // 他は元のまま
          const o = origData.projects[idx];
          return {
            project_id: o.project_id,
            project_role_id: o.project_role_id,
            granted_permission_ids: o.granted_permission_ids
          };
        })
      };
      const res = await axios.put(`/api/v1/users/${userId}/roles_permissions`, {
        roles_permissions: updPayload
      });
      setData(res.data);
      setOrigData(JSON.parse(JSON.stringify(res.data)));
      setEditingProjIds((s) => {
        const ns = new Set(s);
        ns.delete(data.projects[projIndex].project_id);
        return ns;
      });
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  const cancelProj = (projId) => {
    const idx = data.projects.findIndex((p) => p.project_id === projId);
    if (idx < 0) return;
    const pd = origData.projects[idx];
    const nd = { ...data };
    nd.projects[idx] = { ...pd };
    setData(nd);
    setEditingProjIds((s) => {
      const ns = new Set(s);
      ns.delete(projId);
      return ns;
    });
  };

  return (
    <Box>
      <Typography variant='h6' gutterBottom>
        組織ロールと権限
      </Typography>
      <Table>
        <TableHead>
          <TableRow>
            <TableCell>ロール</TableCell>
            {permissions.map((p) => (
              <TableCell key={p.id} align='center'>
                {p.attributes.name}
              </TableCell>
            ))}
            <TableCell>操作</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell>
              {editingOrg ? (
                <FormControl size='small' fullWidth>
                  <InputLabel>ロール</InputLabel>
                  <Select
                    value={data.organization.organization_role_id}
                    label='ロール'
                    onChange={(e) =>
                      setData({
                        ...data,
                        organization: {
                          ...data.organization,
                          organization_role_id: +e.target.value
                        }
                      })
                    }
                  >
                    {orgRoles.map((r) => (
                      <MenuItem key={r.id} value={r.id}>
                        {r.attributes.name}
                      </MenuItem>
                    ))}
                  </Select>
                </FormControl>
              ) : (
                orgRoles.find(
                  (r) => r.id === data.organization.organization_role_id
                )?.attributes.name || '-'
              )}
            </TableCell>
            {permissions.map((p) => (
              <TableCell key={p.id} align='center'>
                {editingOrg ? (
                  <Checkbox
                    size='small'
                    checked={data.organization.granted_permission_ids.includes(
                      p.id
                    )}
                    onChange={() =>
                      setData({
                        ...data,
                        organization: {
                          ...data.organization,
                          granted_permission_ids: toggleSet(
                            data.organization.granted_permission_ids,
                            p.id
                          )
                        }
                      })
                    }
                  />
                ) : data.organization.granted_permission_ids.includes(p.id) ? (
                  '?'
                ) : (
                  ''
                )}
              </TableCell>
            ))}
            <TableCell>
              {editingOrg ? (
                <>
                  <IconButton size='small' onClick={saveOrg}>
                    <SaveIcon />
                  </IconButton>
                  <IconButton size='small' onClick={cancelOrg}>
                    <CloseIcon />
                  </IconButton>
                </>
              ) : (
                <IconButton size='small' onClick={() => setEditingOrg(true)}>
                  <EditIcon />
                </IconButton>
              )}
            </TableCell>
          </TableRow>
        </TableBody>
      </Table>

      <Box mt={4}>
        <Typography variant='h6' gutterBottom>
          プロジェクト別設定
        </Typography>
        <Table>
          <TableHead>
            <TableRow>
              <TableCell>プロジェクト</TableCell>
              <TableCell>ロール</TableCell>
              {permissions.map((p) => (
                <TableCell key={p.id} align='center'>
                  {p.attributes.name}
                </TableCell>
              ))}
              <TableCell>操作</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {data.projects.map((pr, idx) => {
              const isEditing = editingProjIds.has(pr.project_id);
              const roles = projectRolesMap[pr.project_id] || [];
              return (
                <TableRow key={pr.project_id}>
                  <TableCell>{pr.project_id}</TableCell>

                  <TableCell>
                    {isEditing ? (
                      <FormControl size='small' fullWidth>
                        <InputLabel>ロール</InputLabel>
                        <Select
                          value={pr.project_role_id}
                          label='ロール'
                          onChange={(e) => {
                            const arr = [...data.projects];
                            arr[idx].project_role_id = +e.target.value;
                            setData({ ...data, projects: arr });
                          }}
                        >
                          {roles.map((r) => (
                            <MenuItem key={r.id} value={r.id}>
                              {r.attributes.name}
                            </MenuItem>
                          ))}
                        </Select>
                      </FormControl>
                    ) : (
                      roles.find((r) => r.id === pr.project_role_id)?.attributes
                        .name || '-'
                    )}
                  </TableCell>

                  {permissions.map((p) => (
                    <TableCell key={p.id} align='center'>
                      {isEditing ? (
                        <Checkbox
                          size='small'
                          checked={pr.granted_permission_ids.includes(p.id)}
                          onChange={() => {
                            const arr = [...data.projects];
                            arr[idx].granted_permission_ids = toggleSet(
                              arr[idx].granted_permission_ids,
                              p.id
                            );
                            setData({ ...data, projects: arr });
                          }}
                        />
                      ) : pr.granted_permission_ids.includes(p.id) ? (
                        '?'
                      ) : (
                        ''
                      )}
                    </TableCell>
                  ))}

                  <TableCell>
                    {isEditing ? (
                      <>
                        <IconButton size='small' onClick={() => saveProj(idx)}>
                          <SaveIcon />
                        </IconButton>
                        <IconButton
                          size='small'
                          onClick={() => cancelProj(pr.project_id)}
                        >
                          <CloseIcon />
                        </IconButton>
                      </>
                    ) : (
                      <IconButton
                        size='small'
                        onClick={() =>
                          setEditingProjIds((s) =>
                            new Set(s).add(pr.project_id)
                          )
                        }
                      >
                        <EditIcon />
                      </IconButton>
                    )}
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </Box>
    </Box>
  );
}
```

---

### ポイント解説

- **editingOrg** / **editingProjIds** で「編集モード」か管理
- 非編集時はテキスト or ? で「閲覧専用」
- 編集時は MUI の `<Select>`＋`<Checkbox>`＋行単位の `<Save>` / `<Cancel>`
- Save→統一エンドポイント `/roles_permissions` に PUT。一行だけ更新したい場合でも全体ペイロードを送信
- Cancel→`origData` からその行だけロールバック
- サーバ応答後は `data` と `origData` を同期し、編集モード解除

これで、一覧表示＋行単位編集の典型的なUXを満たすUIが完成します。
