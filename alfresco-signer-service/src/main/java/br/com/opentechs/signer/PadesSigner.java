package br.com.opentechs.signer;

import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.interactive.digitalsignature.PDSignature;
import org.apache.pdfbox.pdmodel.interactive.digitalsignature.SignatureInterface;
import org.apache.pdfbox.pdmodel.interactive.digitalsignature.SignatureOptions;
import org.bouncycastle.cert.jcajce.JcaCertStore;
import org.bouncycastle.cms.CMSProcessableByteArray;
import org.bouncycastle.cms.CMSSignedData;
import org.bouncycastle.cms.CMSSignedDataGenerator;
import org.bouncycastle.cms.jcajce.JcaSignerInfoGeneratorBuilder;
import org.bouncycastle.operator.ContentSigner;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;
import org.bouncycastle.operator.jcajce.JcaDigestCalculatorProviderBuilder;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.security.PrivateKey;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import java.util.Arrays;
import java.util.Calendar;

/**
 * Gera assinatura PAdES (PDF + CMS detached embarcado, SubFilter
 * ETSI.CAdES.detached) com a cadeia completa de certificados ICP-Brasil.
 * Produz PAdES-BES, verificavel offline (ITI, Adobe, etc.).
 */
public final class PadesSigner {

    private PadesSigner() { }

    public static byte[] sign(byte[] pdfBytes, PrivateKey privateKey, Certificate[] chain,
                              String reason, String location) throws Exception {

        final X509Certificate signerCert = (X509Certificate) chain[0];

        try (PDDocument document = PDDocument.load(new ByteArrayInputStream(pdfBytes));
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {

            PDSignature signature = new PDSignature();
            signature.setFilter(PDSignature.FILTER_ADOBE_PPKLITE);
            // SubFilter ETSI.CAdES.detached => assinatura PAdES
            signature.setSubFilter(PDSignature.SUBFILTER_ETSI_CADES_DETACHED);
            signature.setName(signerCert.getSubjectX500Principal().getName());
            signature.setReason(reason);
            signature.setLocation(location);
            signature.setSignDate(Calendar.getInstance());

            SignatureInterface signatureInterface = content -> buildCmsSignature(content, privateKey, chain, signerCert);

            SignatureOptions options = new SignatureOptions();
            // Reserva espaco suficiente para a assinatura + cadeia completa.
            options.setPreferredSignatureSize(SignatureOptions.DEFAULT_SIGNATURE_SIZE * 4);

            document.addSignature(signature, signatureInterface, options);
            // saveIncremental preserva o PDF original e anexa a assinatura.
            document.saveIncremental(out);
            return out.toByteArray();
        }
    }

    private static byte[] buildCmsSignature(InputStream content, PrivateKey privateKey,
                                            Certificate[] chain, X509Certificate signerCert) throws IOException {
        try {
            byte[] data = content.readAllBytes();

            CMSSignedDataGenerator generator = new CMSSignedDataGenerator();
            ContentSigner sha256Signer = new JcaContentSignerBuilder("SHA256withRSA")
                    .setProvider("BC").build(privateKey);

            generator.addSignerInfoGenerator(
                    new JcaSignerInfoGeneratorBuilder(
                            new JcaDigestCalculatorProviderBuilder().setProvider("BC").build())
                            .build(sha256Signer, signerCert));

            // Inclui a cadeia completa (folha + intermediarias + raiz ICP-Brasil).
            generator.addCertificates(new JcaCertStore(Arrays.asList(chain)));

            // false => assinatura detached (o conteudo nao vai dentro do CMS).
            CMSSignedData signedData = generator.generate(new CMSProcessableByteArray(data), false);
            return signedData.getEncoded();
        } catch (Exception e) {
            throw new IOException("Erro ao gerar a assinatura CMS/PAdES: " + e.getMessage(), e);
        }
    }
}
