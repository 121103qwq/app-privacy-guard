package org.appprivacy.browser;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import javax.net.ssl.*;
// Reads only a country code into the UI. Address fields are never retained or logged.
public final class ProxyCheck {
    public static boolean isUs(int port) {
        String stage="local_bridge";
        try(Socket local=new Socket()) {
            local.connect(new InetSocketAddress("127.0.0.1",port),5000);local.setSoTimeout(8000);
            stage="proxy_connect";local.getOutputStream().write("CONNECT www.cloudflare.com:443 HTTP/1.1\r\nHost: www.cloudflare.com:443\r\n\r\n".getBytes(StandardCharsets.US_ASCII));
            ByteArrayOutputStream header=new ByteArrayOutputStream();int b;
            while(header.size()<8192&&(b=local.getInputStream().read())!=-1){header.write(b);byte[] bytes=header.toByteArray();int n=bytes.length;if(n>=4&&bytes[n-4]==13&&bytes[n-3]==10&&bytes[n-2]==13&&bytes[n-1]==10)break;}
            if(!new String(header.toByteArray(),StandardCharsets.US_ASCII).matches("(?s)HTTP/1\\.[01] 200 .*")){android.util.Log.i("PrivacyFixture","proxy_check_failed_stage=connect_status");return false;}
            try(SSLSocket secure=(SSLSocket)((SSLSocketFactory)SSLSocketFactory.getDefault()).createSocket(local,"www.cloudflare.com",443,true)){
                stage="verified_tls";SSLParameters parameters=secure.getSSLParameters();parameters.setEndpointIdentificationAlgorithm("HTTPS");secure.setSSLParameters(parameters);secure.setSoTimeout(8000);secure.startHandshake();
                secure.getOutputStream().write("GET /cdn-cgi/trace HTTP/1.1\r\nHost: www.cloudflare.com\r\nConnection: close\r\nAccept-Language: en-US,en;q=0.9\r\n\r\n".getBytes(StandardCharsets.US_ASCII));
                ByteArrayOutputStream reply=new ByteArrayOutputStream();byte[] bytes=new byte[1024];int n;
                while(reply.size()<32768&&(n=secure.getInputStream().read(bytes))!=-1)reply.write(bytes,0,n);
                String text=new String(reply.toByteArray(),StandardCharsets.UTF_8);
                boolean ok=text.startsWith("HTTP/1.1 200")&&text.matches("(?s).*\\r?\\nloc=US\\r?\\n.*");if(!ok)android.util.Log.i("PrivacyFixture","proxy_check_failed_stage=country_or_http_status");return ok;
            }
        }catch(Exception ignored){android.util.Log.i("PrivacyFixture","proxy_check_failed_stage="+stage+";type="+ignored.getClass().getSimpleName());return false;}
    }
}
