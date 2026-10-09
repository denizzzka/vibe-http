module app;

import core.time : seconds;
import std;
import vibe.core;
import vibe.http.client;
import vibe.http.server;
import vibe.inet.url;
import vibe.stream.operations: readAllUTF8;
import vibe.stream.tls;

private enum response_body = "Hello, World!";

private void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.writeBody(response_body);
}

private URL proxyFromEnvironment(string name)
{
	auto value = environment.get(name, "");
	return value.length ? URL.parse(value) : URL.init;
}

private void testProxyRequest(string label, string target_schema, string target_host,
	ushort target_port, URL proxy)
{
	logInfo("Testing %s proxy: %s://%s:%s", label, target_schema, target_host, target_port);

	auto settings = new HTTPClientSettings;
	settings.proxyURL = proxy;
	settings.connectTimeout = 10.seconds;
	settings.tlsContextSetup = (TLSContext ctx) @safe nothrow {
		try ctx.peerValidationMode = TLSPeerValidationMode.none;
		catch (Exception) {}
	};

	auto url = URL(target_schema, target_host, target_port, InetPath("/"));
	requestHTTP(url, (scope HTTPClientRequest req) {}, (scope HTTPClientResponse res) {
		enforce(res.statusCode == HTTPStatus.ok, "Unexpected status code: " ~ res.statusCode.to!string);
		enforce(res.bodyReader.readAllUTF8() == response_body, "Unexpected response body.");
	}, settings);
}

void main()
{
	// The target server listens on "::" so that the proxy can reach it over
	// both IPv4 and IPv6.
	auto settings = new HTTPServerSettings;
	settings.port = 0;
	settings.bindAddresses = ["::"];
	auto listener = listenHTTP(settings, &handleRequest);
	scope(exit) listener.stopListening();
	auto target_port = listener.bindAddresses[0].port;

	static immutable proxies = [
		tuple("socks5", "PROXY_SOCKS5"),
		tuple("socks5+auth", "PROXY_SOCKS5_AUTH"),
	];

	foreach (target_host; ["127.0.0.1", "localhost"]) {
		foreach (p; proxies) {
			auto proxy = proxyFromEnvironment(p[1]);
			if (proxy.schema !is null)
				testProxyRequest(p[0], "http", target_host, target_port, proxy);
		}
	}

	logInfo("Proxy test finished successfully.");
}
