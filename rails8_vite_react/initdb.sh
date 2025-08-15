set -ue
rails db:drop db:create db:migrate
rails db:seed
