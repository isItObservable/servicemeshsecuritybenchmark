# Copyright Istio Authors
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
FROM mysql:8.0

# Copy initialization script
COPY mysqldb-init.sql /docker-entrypoint-initdb.d/

# Environment variables
ENV MYSQL_ROOT_PASSWORD=password
ENV MYSQL_DATABASE=test

# MySQL 8.0 compatible configuration
# Note: --default-authentication-plugin was removed in MySQL 8.4+
# Using mysql_native_password for compatibility
CMD ["mysqld", \
     "--character-set-server=utf8mb4", \
     "--collation-server=utf8mb4_unicode_ci", \
     "--bind-address=0.0.0.0"]