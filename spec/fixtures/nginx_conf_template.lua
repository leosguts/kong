return [[daemon on;
worker_processes  ${worker_num};
error_log  ${base_path}/${logs_dir}/error.log info;
pid        ${base_path}/${logs_dir}/nginx.pid;
worker_rlimit_nofile 8192;

events {
  worker_connections  1024;
}

http {
  lua_shared_dict server_values 512k;

  init_worker_by_lua_block {
    local server_values = ngx.shared.server_values
    server_values:set("healthy", true)
    server_values:set("timeout", false)
  }

  default_type application/json;
  access_log   ${base_path}/${logs_dir}/access.log;
  sendfile     on;
  tcp_nopush   on;
  server_names_hash_bucket_size 128;

  server {
# if protocol ~= 'https' then
    listen ${http_port};
# else
    listen ${http_port} ssl;
    ssl_certificate     ${cert_path}/kong_spec.crt;
    ssl_certificate_key ${cert_path}/kong_spec.key;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers   HIGH:!aNULL:!MD5;
#end
# if check_hostname then
    server_name ${host};
#end

    location = /healthy {
      access_by_lua_block {
        ngx.shared.server_values:set("healthy", true)
        ngx.shared.server_values:set("timeout", false)
      }

      content_by_lua_block {
        ngx.say("server ", ngx.var.server_name, " is now healthy")
        return ngx.exit(ngx.HTTP_OK)
      }
    }

    location = /unhealthy {
      access_by_lua_block {
        ngx.shared.server_values:set("healthy", false)
      }

      content_by_lua_block {
        ngx.say("server ", ngx.var.server_name, " is now unhealthy")
        return ngx.exit(ngx.HTTP_OK)
      }
    }

    location = /timeout {
      access_by_lua_block {
        ngx.shared.server_values:set("timeout", true)
      }

      content_by_lua_block {
        ngx.say("server ", ngx.var.server_name, " is timeouting now")
        return ngx.exit(ngx.HTTP_OK)
      }
    }

    location = /status {
      access_by_lua_block {
        local server_values = ngx.shared.server_values
        if server_values:get("timeout") == true then
          ngx.sleep(2)
        end
        local status = server_values:get("healthy") and
                        ngx.HTTP_OK or ngx.HTTP_INTERNAL_SERVER_ERROR

        ngx.log(ngx.INFO, "[COUNT] status ", status)
        ngx.exit(status)
      }
    }

    location / {
      access_by_lua_block {
          local cjson = require("cjson")
          local server_values = ngx.shared.server_values
          local status

          if server_values:get("healthy") == true then
            status = ngx.HTTP_OK
          else
            status = ngx.HTTP_INTERNAL_SERVER_ERROR
          end

          if server_values:get("timeout") == true then
            ngx.sleep(2)
          end

          ngx.log(ngx.INFO, "[COUNT] slash ", status)

          ngx.exit(status)
      }
    }
  }
# if check_hostname then
  server {
    listen ${http_port} default_server;
    server_name _;
    return 400;
  }
# end

}
]]
