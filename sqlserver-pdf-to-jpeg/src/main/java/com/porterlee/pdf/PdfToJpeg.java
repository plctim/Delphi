package com.porterlee.pdf;

import com.microsoft.sqlserver.javalangextension.AbstractSqlServerExtensionExecutor;
import com.microsoft.sqlserver.javalangextension.PrimitiveDataset;

import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.rendering.ImageType;
import org.apache.pdfbox.rendering.PDFRenderer;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;

/**
 * SQL Server Java Language Extension executor that rasterizes every page of a PDF
 * into a JPEG image.
 *
 * <p>Invoked from T-SQL via {@code sp_execute_external_script}.</p>
 *
 * <p><b>Input dataset</b> (the result of {@code @input_data_1}) must be two columns:</p>
 * <ol start="0">
 *   <li>{@code DocId}    - INT          (an identifier echoed back on each output row)</li>
 *   <li>{@code PdfBytes} - VARBINARY(MAX) (the PDF file content)</li>
 * </ol>
 *
 * <p><b>Output dataset</b> (declare with {@code WITH RESULT SETS}) is three columns,
 * one row per rendered page:</p>
 * <ol start="0">
 *   <li>{@code DocId}      - INT</li>
 *   <li>{@code PageNumber} - INT (1-based)</li>
 *   <li>{@code JpegBytes}  - VARBINARY(MAX)</li>
 * </ol>
 *
 * <p><b>Parameters</b> (via {@code @params}):</p>
 * <ul>
 *   <li>{@code @dpi INT} - optional render resolution in DPI (default 150).</li>
 * </ul>
 */
public class PdfToJpeg extends AbstractSqlServerExtensionExecutor {

    /** Default render resolution if no {@code @dpi} parameter is supplied. */
    private static final float DEFAULT_DPI = 150f;

    static {
        // PDFBox rendering uses java.awt; force headless so it works on a server
        // with no display. Harmless if already set by the extension's JRE.
        System.setProperty("java.awt.headless", "true");
    }

    public PdfToJpeg() {
        // Required SDK handshake: declare protocol version and the dataset type
        // used for the input/output exchange with SQL Server.
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

        int[] docIds = input.getIntColumn(0);
        byte[][] pdfBlobs = input.getBinaryColumn(1);
        int rowCount = pdfBlobs.length;

        // Output is variable length (sum of page counts across all input rows),
        // so accumulate in lists before flattening to the column arrays the SDK wants.
        List<Integer> outDocIds = new ArrayList<>();
        List<Integer> outPageNumbers = new ArrayList<>();
        List<byte[]> outJpegs = new ArrayList<>();

        for (int row = 0; row < rowCount; row++) {
            byte[] pdf = pdfBlobs[row];
            if (pdf == null || pdf.length == 0) {
                // Skip NULL/empty blobs rather than failing the whole batch.
                continue;
            }
            renderDocument(docIds[row], pdf, dpi, outDocIds, outPageNumbers, outJpegs);
        }

        return buildOutput(outDocIds, outPageNumbers, outJpegs);
    }

    /** Render one PDF document, appending one output row per page. */
    private void renderDocument(int docId,
                                byte[] pdf,
                                float dpi,
                                List<Integer> outDocIds,
                                List<Integer> outPageNumbers,
                                List<byte[]> outJpegs) {
        try (PDDocument document = PDDocument.load(pdf)) {
            PDFRenderer renderer = new PDFRenderer(document);
            int pageCount = document.getNumberOfPages();
            for (int pageIndex = 0; pageIndex < pageCount; pageIndex++) {
                // ImageType.RGB (no alpha) because JPEG cannot encode transparency.
                BufferedImage image = renderer.renderImageWithDPI(pageIndex, dpi, ImageType.RGB);
                outDocIds.add(docId);
                outPageNumbers.add(pageIndex + 1);
                outJpegs.add(toJpeg(image));
            }
        } catch (IOException e) {
            throw new RuntimeException(
                "Failed to render PDF for DocId " + docId + ": " + e.getMessage(), e);
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
                                         List<byte[]> jpegs) {
        int n = jpegs.size();
        int[] docIdColumn = new int[n];
        int[] pageNumberColumn = new int[n];
        byte[][] jpegColumn = new byte[n][];
        for (int i = 0; i < n; i++) {
            docIdColumn[i] = docIds.get(i);
            pageNumberColumn[i] = pageNumbers.get(i);
            jpegColumn[i] = jpegs.get(i);
        }

        PrimitiveDataset output = new PrimitiveDataset();
        output.addColumnMetadata(0, "DocId", Types.INTEGER, 0, 0);
        output.addColumnMetadata(1, "PageNumber", Types.INTEGER, 0, 0);
        output.addColumnMetadata(2, "JpegBytes", Types.VARBINARY, 0, 0);

        output.addIntColumn(0, docIdColumn, null);
        output.addIntColumn(1, pageNumberColumn, null);
        output.addBinaryColumn(2, jpegColumn);

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
