package com.porterlee.pdf;

import com.microsoft.sqlserver.javalangextension.AbstractSqlServerExtensionExecutor;
import com.microsoft.sqlserver.javalangextension.PrimitiveDataset;

import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.rendering.ImageType;
import org.apache.pdfbox.rendering.PDFRenderer;
import org.apache.pdfbox.text.PDFTextStripper;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;

/**
 * SQL Server Java Language Extension executor that, for every page of a PDF,
 * produces a JPEG image and extracts the page's text.
 *
 * <p>Invoked from T-SQL via {@code sp_execute_external_script}.</p>
 *
 * <p><b>Input dataset</b> ({@code @input_data_1}) must be two columns:</p>
 * <ol start="0">
 *   <li>{@code DocId}    - INT</li>
 *   <li>{@code PdfBytes} - VARBINARY(MAX)</li>
 * </ol>
 *
 * <p><b>Output dataset</b> ({@code WITH RESULT SETS}) is four columns, one row per page:</p>
 * <ol start="0">
 *   <li>{@code DocId}      - INT</li>
 *   <li>{@code PageNumber} - INT (1-based)</li>
 *   <li>{@code JpegBytes}  - VARBINARY(MAX)</li>
 *   <li>{@code PageText}   - NVARCHAR(MAX) (empty for pages with no text layer, e.g. scans)</li>
 * </ol>
 *
 * <p><b>Parameters</b> ({@code @params}):</p>
 * <ul>
 *   <li>{@code @dpi INT}          - optional render resolution (default 150).</li>
 *   <li>{@code @renderImage BIT}  - optional; when 0, JpegBytes is NULL and no image is rendered (default 1).</li>
 *   <li>{@code @extractText BIT}  - optional; when 0, PageText is NULL and no text is extracted (default 1).</li>
 * </ul>
 * <p>If both {@code @renderImage} and {@code @extractText} are 0, an exception is thrown.</p>
 */
public class PdfToJpeg extends AbstractSqlServerExtensionExecutor {

    /** Default render resolution if no {@code @dpi} parameter is supplied. */
    private static final float DEFAULT_DPI = 150f;

    static {
        // PDFBox rendering uses java.awt; force headless so it works on a server.
        System.setProperty("java.awt.headless", "true");
    }

    public PdfToJpeg() {
        executorExtensionVersion = SQLSERVER_JAVA_LANG_EXTENSION_V1;
        executorInputDatasetClassName = PrimitiveDataset.class.getName();
        executorOutputDatasetClassName = PrimitiveDataset.class.getName();
    }

    // NOTE: intentionally NOT @Override. The SDK base method is
    // execute(AbstractSqlServerExtensionDataset, ...); this PrimitiveDataset
    // overload is located and invoked reflectively by the extension based on
    // executorInputDatasetClassName / executorOutputDatasetClassName.
    public PrimitiveDataset execute(PrimitiveDataset input, LinkedHashMap<String, Object> params) {
        validateInput(input);

        float dpi = resolveDpi(params);
        boolean renderImage = resolveFlag(params, "renderImage", true);
        boolean extractText = resolveFlag(params, "extractText", true);

        // At least one output must be requested.
        if (!renderImage && !extractText) {
            throw new IllegalArgumentException(
                "Nothing to do: both @renderImage and @extractText are 0. Request at least one.");
        }

        int[] docIds = input.getIntColumn(0);
        byte[][] pdfBlobs = input.getBinaryColumn(1);
        int rowCount = pdfBlobs.length;

        // Output length varies (sum of page counts); accumulate then flatten.
        List<Integer> outDocIds = new ArrayList<>();
        List<Integer> outPageNumbers = new ArrayList<>();
        List<byte[]> outJpegs = new ArrayList<>();
        List<String> outTexts = new ArrayList<>();

        for (int row = 0; row < rowCount; row++) {
            byte[] pdf = pdfBlobs[row];
            if (pdf == null || pdf.length == 0) {
                continue;
            }
            renderDocument(docIds[row], pdf, dpi, renderImage, extractText,
                           outDocIds, outPageNumbers, outJpegs, outTexts);
        }

        return buildOutput(outDocIds, outPageNumbers, outJpegs, outTexts);
    }

    /**
     * Process one PDF: append one output row per page. JPEG and/or text are
     * produced per the flags; a skipped output is left NULL.
     */
    private void renderDocument(int docId,
                                byte[] pdf,
                                float dpi,
                                boolean renderImage,
                                boolean extractText,
                                List<Integer> outDocIds,
                                List<Integer> outPageNumbers,
                                List<byte[]> outJpegs,
                                List<String> outTexts) {
        try (PDDocument document = PDDocument.load(pdf)) {
            PDFRenderer renderer = renderImage ? new PDFRenderer(document) : null;

            PDFTextStripper stripper = null;
            if (extractText) {
                stripper = new PDFTextStripper();
                stripper.setSortByPosition(true);   // natural reading order
            }

            int pageCount = document.getNumberOfPages();
            for (int pageIndex = 0; pageIndex < pageCount; pageIndex++) {
                // Image (ImageType.RGB: JPEG can't carry transparency) -- only if requested
                byte[] jpeg = null;
                if (renderImage) {
                    BufferedImage image = renderer.renderImageWithDPI(pageIndex, dpi, ImageType.RGB);
                    jpeg = toJpeg(image);
                }

                // Text for just this page -- only if requested (empty if no text layer)
                String text = null;
                if (extractText) {
                    stripper.setStartPage(pageIndex + 1);
                    stripper.setEndPage(pageIndex + 1);
                    String t = stripper.getText(document);
                    text = (t != null) ? t : "";
                }

                outDocIds.add(docId);
                outPageNumbers.add(pageIndex + 1);
                outJpegs.add(jpeg);     // null -> SQL NULL
                outTexts.add(text);     // null -> SQL NULL
            }
        } catch (IOException e) {
            throw new RuntimeException(
                "Failed to process PDF for DocId " + docId + ": " + e.getMessage(), e);
        }
    }

    /** Encode a rendered page as JPEG bytes. */
    private byte[] toJpeg(BufferedImage image) {
        try (ByteArrayOutputStream buffer = new ByteArrayOutputStream()) {
            if (!ImageIO.write(image, "jpeg", buffer)) {
                throw new IOException("No JPEG ImageWriter is registered in this JRE.");
            }
            return buffer.toByteArray();
        } catch (IOException e) {
            throw new RuntimeException("JPEG encoding failed: " + e.getMessage(), e);
        }
    }

    /** Flatten the accumulated rows into a PrimitiveDataset for SQL Server. */
    private PrimitiveDataset buildOutput(List<Integer> docIds,
                                         List<Integer> pageNumbers,
                                         List<byte[]> jpegs,
                                         List<String> texts) {
        int n = jpegs.size();
        int[] docIdColumn = new int[n];
        int[] pageNumberColumn = new int[n];
        byte[][] jpegColumn = new byte[n][];
        String[] textColumn = new String[n];
        for (int i = 0; i < n; i++) {
            docIdColumn[i] = docIds.get(i);
            pageNumberColumn[i] = pageNumbers.get(i);
            jpegColumn[i] = jpegs.get(i);   // null element -> SQL NULL (image not requested)
            textColumn[i] = texts.get(i);   // null element -> SQL NULL (text not requested)
        }

        PrimitiveDataset output = new PrimitiveDataset();
        output.addColumnMetadata(0, "DocId", Types.INTEGER, 0, 0);
        output.addColumnMetadata(1, "PageNumber", Types.INTEGER, 0, 0);
        output.addColumnMetadata(2, "JpegBytes", Types.VARBINARY, 0, 0);
        output.addColumnMetadata(3, "PageText", Types.NVARCHAR, 0, 0);

        output.addIntColumn(0, docIdColumn, null);
        output.addIntColumn(1, pageNumberColumn, null);
        output.addBinaryColumn(2, jpegColumn);
        output.addStringColumn(3, textColumn);

        return output;
    }

    private float resolveDpi(LinkedHashMap<String, Object> params) {
        if (params != null) {
            Object dpi = params.get("dpi");
            if (dpi instanceof Integer && (Integer) dpi > 0) {
                return (Integer) dpi;
            }
        }
        return DEFAULT_DPI;
    }

    /**
     * Resolve a BIT flag passed via @params. A SQL BIT arrives as Boolean, but
     * tolerate Integer/Short (0/1) too. Missing/null falls back to the default.
     */
    private boolean resolveFlag(LinkedHashMap<String, Object> params, String name, boolean defaultValue) {
        if (params == null) {
            return defaultValue;
        }
        Object v = params.get(name);
        if (v == null) {
            return defaultValue;
        }
        if (v instanceof Boolean) {
            return (Boolean) v;
        }
        if (v instanceof Number) {
            return ((Number) v).intValue() != 0;
        }
        return defaultValue;
    }

    private void validateInput(PrimitiveDataset input) {
        if (input == null || input.getColumnCount() < 2) {
            throw new IllegalArgumentException(
                "Expected input schema (DocId INT, PdfBytes VARBINARY(MAX)).");
        }
        if (input.getColumnType(0) != Types.INTEGER) {
            throw new IllegalArgumentException("Input column 0 (DocId) must be INT.");
        }
        int blobType = input.getColumnType(1);
        if (blobType != Types.VARBINARY
                && blobType != Types.LONGVARBINARY
                && blobType != Types.BINARY) {
            throw new IllegalArgumentException(
                "Input column 1 (PdfBytes) must be VARBINARY(MAX).");
        }
    }
}
