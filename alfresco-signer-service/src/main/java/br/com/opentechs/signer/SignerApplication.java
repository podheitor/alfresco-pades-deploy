package br.com.opentechs.signer;

import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import java.security.Security;

/**
 * Microsservico de assinatura digital PAdES (ICP-Brasil) para o Alfresco - Cliente.
 * Assina PDFs com certificados A1 (.p12/.pfx) do cofre, via REST.
 */
@SpringBootApplication
public class SignerApplication {

    public static void main(String[] args) {
        // Provider BouncyCastle para a geracao da assinatura CMS/PKCS7.
        Security.addProvider(new BouncyCastleProvider());
        SpringApplication.run(SignerApplication.class, args);
    }
}
