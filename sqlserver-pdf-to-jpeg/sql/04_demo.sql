/* ============================================================================
   04 - End-to-end demo.
   Creates a sample table, loads a PDF into the column, and runs the converter.
   ============================================================================ */

USE [YourDatabase];   -- <-- change to your database
GO

-- Sample storage table (skip if you already have one).
IF OBJECT_ID(N'dbo.Documents', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Documents
    (
        DocId    INT IDENTITY(1, 1) PRIMARY KEY,
        FileName NVARCHAR(260)  NULL,
        PdfBytes VARBINARY(MAX) NOT NULL
    );
END
GO

-- Load a PDF from disk into the column (path must be readable by the SQL service account).
INSERT into Documents (FileName, PdfBytes)
SELECT N'sample.pdf', BulkColumn
FROM OPENROWSET(BULK N'C:\Temp\sample.pdf', SINGLE_BLOB) AS src;
GO

-- (A) Just stream the pages back to the client.
EXEC dbo.ConvertPdfToJpeg @DocId = 1, @Dpi = 150;
GO

-- (B) Capture the pages into a table and inspect sizes + text length.
DECLARE @pages TABLE
(
    DocId      INT,
    PageNumber INT,
    JpegBytes  VARBINARY(MAX),
    PageText   NVARCHAR(MAX)
);

INSERT @pages (DocId, PageNumber, JpegBytes, PageText)
EXEC dbo.ConvertPdfToJpeg @DocId = 1, @Dpi = 150;

SELECT DocId,
       PageNumber,
       DATALENGTH(JpegBytes)   AS JpegSizeBytes,
       LEN(PageText)           AS TextLength,
       LEFT(PageText, 80)      AS TextPreview
FROM @pages
ORDER BY PageNumber;
GO

/* ============================================================================
   (D) Optional outputs: image and text are independently switchable.
   ============================================================================ */

-- (D1) BOTH image and text (the default) -----------------------------------
EXEC dbo.ConvertPdfToJpeg @DocId = 1, @RenderImage = 1, @ExtractText = 1;
GO

-- (D2) IMAGE ONLY -- PageText comes back NULL, no text work is done ---------
DECLARE @imgOnly TABLE (DocId INT, PageNumber INT, JpegBytes VARBINARY(MAX), PageText NVARCHAR(MAX));
INSERT @imgOnly EXEC dbo.ConvertPdfToJpeg @DocId = 1, @ExtractText = 0;

SELECT PageNumber,
       DATALENGTH(JpegBytes) AS JpegSizeBytes,   -- populated
       PageText                                   -- expect NULL
FROM @imgOnly ORDER BY PageNumber;
GO

-- (D3) TEXT ONLY -- JpegBytes comes back NULL, no image is rendered ---------
DECLARE @txtOnly TABLE (DocId INT, PageNumber INT, JpegBytes VARBINARY(MAX), PageText NVARCHAR(MAX));
INSERT @txtOnly EXEC dbo.ConvertPdfToJpeg @DocId = 1, @RenderImage = 0;

SELECT PageNumber,
       JpegBytes,                  -- expect NULL
       LEN(PageText) AS TextLength -- populated for digital PDFs
FROM @txtOnly ORDER BY PageNumber;
GO

-- (D4) NEITHER -- raises error 50005 (uncomment to see the exception) -------
-- EXEC dbo.ConvertPdfToJpeg @DocId = 1, @RenderImage = 0, @ExtractText = 0;
-- GO

/* ============================================================================
   (E) Generic, any-table proc (sql/08): outputs chosen by target column names.
       Omit @JpegColumn (NULL) to skip images; omit @TextColumn to skip text.
   ============================================================================ */
/*
-- Image + text into dbo.DocumentsPages:
EXEC dbo.RenderPdfTableToJpegs @SourceTable=N'Documents', @KeyColumn=N'DocId',
     @PdfColumn=N'PdfBytes', @TargetTable=N'DocumentsPages';
SELECT KeyValue, PageNumber, DATALENGTH(JpegBytes) AS JpegSizeBytes, LEN(PageText) AS TextLength
FROM dbo.DocumentsPages ORDER BY KeyValue, PageNumber;

-- Text only into a separate table dbo.DocumentsText (no JpegBytes column created):
EXEC dbo.RenderPdfTableToJpegs @SourceTable=N'Documents', @KeyColumn=N'DocId',
     @PdfColumn=N'PdfBytes', @TargetTable=N'DocumentsText', @JpegColumn=NULL;
SELECT KeyValue, PageNumber, LEN(PageText) AS TextLength FROM dbo.DocumentsText ORDER BY KeyValue, PageNumber;
*/

/* (C) Optional: persist each page to disk via OLE automation, or just store the
   rows in a JpegPages table. Example persistent sink:

   CREATE TABLE dbo.PdfPageImages
   (
       DocId      INT          NOT NULL,
       PageNumber INT          NOT NULL,
       JpegBytes  VARBINARY(MAX) NOT NULL,
       PageText   NVARCHAR(MAX) NULL,
       CONSTRAINT PK_PdfPageImages PRIMARY KEY (DocId, PageNumber)
   );

   INSERT dbo.PdfPageImages (DocId, PageNumber, JpegBytes, PageText)
   EXEC dbo.ConvertPdfToJpeg @DocId = 1, @Dpi = 150;
*/
