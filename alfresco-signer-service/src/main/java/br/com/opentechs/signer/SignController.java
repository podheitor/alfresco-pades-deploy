package br.com.opentechs.signer;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.cert.Certificate;

/**
 * Endpoints REST do servico de assinatura.
 *   GET  /health        -> verificacao de saude
 *   POST /sign          -> assina um PDF (multipart) com um A1 do cofre
 */
@RestController
public class SignController {

    /** Diretorio do cofre de certificados A1 (.p12/.pfx). */
    @Value("${signer.certsDir:/opt/alfresco/certificados}")
    private String certsDir;

    @GetMapping("/health")
    public String health() {
        return "OK";
    }

    /**
     * Assina um PDF no padrao PAdES.
     * Parametros (multipart/form-data):
     *   file      - o PDF a ser assinado (obrigatorio)
     *   cert      - nome do arquivo .p12/.pfx no cofre (ex.: fulano.p12)
     *   password  - senha do certificado A1
     *   reason    - (opcional) motivo da assinatura
     *   location  - (opcional) local
     */
    @PostMapping(value = "/sign", produces = MediaType.APPLICATION_PDF_VALUE)
    public ResponseEntity<byte[]> sign(
            @RequestParam("file") MultipartFile file,
            @RequestParam("cert") String cert,
            @RequestParam("password") String password,
            @RequestParam(value = "reason", defaultValue = "Assinatura digital ICP-Brasil") String reason,
            @RequestParam(value = "location", defaultValue = "Brasil") String location) throws Exception {

        // Protecao contra path traversal: o cert deve estar dentro do cofre.
        Path baseDir = Paths.get(certsDir).toAbsolutePath().normalize();
        Path p12 = baseDir.resolve(cert).normalize();
        if (!p12.startsWith(baseDir)) {
            return ResponseEntity.badRequest()
                    .body("Parametro 'cert' invalido.".getBytes());
        }
        if (!Files.isRegularFile(p12)) {
            return ResponseEntity.status(404)
                    .body(("Certificado nao encontrado no cofre: " + cert).getBytes());
        }

        KeyStore ks = KeyStore.getInstance("PKCS12");
        try (InputStream is = Files.newInputStream(p12)) {
            ks.load(is, password.toCharArray());
        }
        String alias = ks.aliases().nextElement();
        PrivateKey privateKey = (PrivateKey) ks.getKey(alias, password.toCharArray());
        Certificate[] chain = ks.getCertificateChain(alias);
        if (chain == null || chain.length == 0) {
            chain = new Certificate[]{ ks.getCertificate(alias) };
        }

        byte[] signed = PadesSigner.sign(file.getBytes(), privateKey, chain, reason, location);

        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"assinado.pdf\"")
                .contentType(MediaType.APPLICATION_PDF)
                .body(signed);
    }
}
