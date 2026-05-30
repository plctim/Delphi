/* ============================================================================
   03 - Wrapper stored procedure.
   Pulls one PDF out of a VARBINARY(MAX) column and returns one row per page.
   Adjust the table/column names in @input_data_1 to match your schema.
   ============================================================================ */

USE [YourDatabase];   -- <-- change to your database
GO

CREATE OR ALTER PROCEDURE dbo.ConvertPdfToJpeg
    @DocId INT,
    @Dpi   INT = 150
AS
BEGIN
    SET NOCOUNT ON;

    EXEC sp_execute_external_script
        @language     = N'Java',
        @script       = N'com.porterlee.pdf.PdfToJpeg',
        -- The input query becomes the executor's input dataset.
        -- @id is supplied through @params below.
        @input_data_1 = N'SELECT DocId, PdfBytes FROM dbo.Documents WHERE DocId = @id',
        @params       = N'@id INT, @dpi INT',
        @id           = @DocId,
        @dpi          = @Dpi
    WITH RESULT SETS (
        (
            DocId      INT,
            PageNumber INT,
            JpegBytes  VARBINARY(MAX),
            PageText   NVARCHAR(MAX)
        )
    );
END
GO
