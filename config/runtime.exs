import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/feed_pug start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :feed_pug, FeedPugWeb.Endpoint, server: true
end

config :feed_pug, FeedPugWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Prefer discrete POSTGRES_* vars (the StackGres/Argo convention — avoids
  # mangling passwords with URL-significant characters); fall back to a single
  # DATABASE_URL when provided.
  repo_connection =
    cond do
      url = System.get_env("DATABASE_URL") ->
        [url: url]

      host = System.get_env("POSTGRES_HOST") ->
        [
          hostname: host,
          port: String.to_integer(System.get_env("POSTGRES_PORT") || "5432"),
          database: System.get_env("POSTGRES_DB") || "feed_pug",
          username: System.get_env("POSTGRES_USER") || raise("POSTGRES_USER is missing"),
          password: System.get_env("POSTGRES_PASSWORD") || raise("POSTGRES_PASSWORD is missing")
        ]

      true ->
        raise """
        No database configuration. Set DATABASE_URL, or the discrete
        POSTGRES_HOST / POSTGRES_PORT / POSTGRES_DB / POSTGRES_USER / POSTGRES_PASSWORD.
        """
    end

  config :feed_pug,
         FeedPug.Repo,
         [
           pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
           socket_options: maybe_ipv6
         ] ++ repo_connection

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :feed_pug, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # libcluster — Kubernetes lookup of peer pods so Phoenix.PubSub fans the live
  # newsfeed across replicas. Only enabled when LIBCLUSTER_KUBERNETES=true (set
  # in the multi-replica deployment); otherwise the topology list stays empty
  # and Application.start skips the Cluster supervisor entirely. RBAC (pods +
  # endpoints) is granted to the `feed-pug` ServiceAccount in app.yml; the node
  # name is `feed_pug@<pod-ip>` (rel/env.sh.eex).
  if System.get_env("LIBCLUSTER_KUBERNETES") == "true" do
    config :libcluster,
      topologies: [
        feed_pug: [
          strategy: Cluster.Strategy.Kubernetes,
          config: [
            mode: :ip,
            kubernetes_selector: "name=feedpug",
            kubernetes_service_name: "feedpug-headless",
            kubernetes_node_basename: "feed_pug",
            kubernetes_namespace: System.get_env("POD_NAMESPACE") || "feedpug",
            polling_interval: 10_000
          ]
        ]
      ]
  end

  # Mailer adapter selection:
  #
  #   * SMTP_RELAY set  → Swoosh.Adapters.SMTP (via gen_smtp)
  #   * otherwise       → Swoosh.Adapters.Logger
  #
  # The Logger adapter doesn't actually send mail — it logs the rendered email
  # at :info — but it gets us off Swoosh.Adapters.Local (the dev mailbox), so the
  # magic-link login flow at least leaves a trail in the pod log when SMTP isn't
  # configured.
  #
  # Map env-string to a literal atom. String.to_existing_atom/1 doesn't work
  # here in a release: runtime.exs runs before the application that owns these
  # atoms has loaded, so the atoms aren't in the table yet.
  smtp_tri = fn var, default ->
    case System.get_env(var, default) do
      "always" -> :always
      "if_available" -> :if_available
      "never" -> :never
      other -> raise "#{var} must be one of always|if_available|never, got: #{inspect(other)}"
    end
  end

  # Eager-load the OS CA bundle into OTP's public_key cache. Without this,
  # :public_key.cacerts_get/0 returns :undefined, and gen_smtp's internal
  # default tls_options injects cacerts: :undefined — which :ssl then rejects as
  # incompatible with verify: :verify_peer, clobbering our explicit cacertfile.
  case :public_key.cacerts_load() do
    :ok ->
      :ok

    {:error, reason} ->
      require Logger
      Logger.warning("public_key:cacerts_load failed: #{inspect(reason)} — TLS verify may fail")
  end

  smtp_cacertfile = System.get_env("SMTP_CACERTFILE", "/etc/ssl/certs/ca-certificates.crt")

  smtp_verify =
    case System.get_env("SMTP_TLS_VERIFY", "verify_peer") do
      "verify_peer" -> :verify_peer
      "verify_none" -> :verify_none
      other -> raise "SMTP_TLS_VERIFY must be verify_peer or verify_none, got: #{inspect(other)}"
    end

  # Resolve the CA store NOW (after cacerts_load) rather than letting the
  # downstream stack call cacerts_get/0 lazily — gen_smtp / ssl tends to evaluate
  # it in a context where it still returns :undefined. Passing cacerts: <list>
  # explicitly is unambiguous.
  smtp_cacerts =
    case :public_key.cacerts_get() do
      certs when is_list(certs) and certs != [] -> certs
      _ -> nil
    end

  mailer_opts =
    if relay = System.get_env("SMTP_RELAY") do
      tls_options =
        [
          verify: smtp_verify,
          server_name_indication: String.to_charlist(relay),
          depth: 99
        ] ++
          cond do
            smtp_verify != :verify_peer -> []
            is_list(smtp_cacerts) -> [cacerts: smtp_cacerts]
            true -> [cacertfile: smtp_cacertfile]
          end

      tls_versions = [:"tlsv1.2", :"tlsv1.3"]

      # gen_smtp 1.2 has two TLS paths with different option keys: implicit TLS
      # (ssl: true, port 465) reads sockopts; STARTTLS (tls: …) reads tls_options.
      # Put the same opts on both so either relay setup verifies correctly.
      ssl_opts = [{:versions, tls_versions} | tls_options]

      [
        adapter: Swoosh.Adapters.SMTP,
        relay: relay,
        port: String.to_integer(System.get_env("SMTP_PORT", "587")),
        username: System.get_env("SMTP_USERNAME"),
        password: System.get_env("SMTP_PASSWORD"),
        tls: smtp_tri.("SMTP_TLS", "if_available"),
        ssl: System.get_env("SMTP_SSL", "false") == "true",
        auth: smtp_tri.("SMTP_AUTH", "if_available"),
        allowed_tls_versions: tls_versions,
        sockopts: ssl_opts,
        tls_options: ssl_opts,
        retries: 1,
        no_mx_lookups: false
      ]
    else
      [adapter: Swoosh.Adapters.Logger, level: :info]
    end

  config :feed_pug, FeedPug.Mailer, mailer_opts

  config :feed_pug, FeedPug.Mailer,
    from_name: System.get_env("MAIL_FROM_NAME", "FeedPug"),
    from_address: System.get_env("MAIL_FROM_ADDRESS") || "noreply@#{host}"

  config :feed_pug, FeedPugWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :feed_pug, FeedPugWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :feed_pug, FeedPugWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :feed_pug, FeedPug.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
