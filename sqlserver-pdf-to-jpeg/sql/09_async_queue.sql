/* ============================================================================
   ASYNC queue version (bulk-safe).

   Instead of rendering inside the DML transaction, the trigger only ENQUEUES
   the changed keys (fast, transactional). A SQL Agent job periodically drains
   the queue out-of-band and calls dbo.RenderPdfTableToJpegs.

   Benefits over the synchronous trigger in 08_generic_render_and_triggers.sql:
     - INSERT/UPDATE returns immediately; rendering never blocks the writer.
     - A render failure does NOT roll back the user's write.
     - Failures are isolated to a dead-letter table instead of retrying forever.

   IMPORTANT: per source table, install EITHER the synchronous trigger (file 08)
   OR the enqueue trigger below -- not both.

   Requires dbo.RenderPdfTableToJpegs (file 08) and SQL Server 2017+ (STRING_AGG).
   ============================================================================ */

USE [YourDatabase];   -- <-- change to your database
GO

-- ---------------------------------------------------------------------------
-- Work queue. Each row carries the full render recipe so the drain proc can
-- service any number of different source tables generically.
-- ---------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.PdfRenderQueue', N'U') IS NULL
CREATE TABLE dbo.PdfRenderQueue
(
    QueueId      BIGINT IDENTITY(1,1) PRIMARY KEY,
    SourceSchema SYSNAME   NOT NULL CONSTRAINT DF_PdfRenderQueue_SrcSchema DEFAULT N'dbo',
    SourceTable  SYSNAME   NOT NULL,
    KeyColumn    SYSNAME   NOT NULL,
    PdfColumn    SYSNAME   NOT NULL,
    TargetSchema SYSNAME   NOT NULL CONSTRAINT DF_PdfRenderQueue_TgtSchema DEFAULT N'dbo',
    TargetTable  SYSNAME   NOT NULL,
    KeyValue     INT       NOT NULL,
    Dpi          INT       NOT NULL CONSTRAINT DF_PdfRenderQueue_Dpi DEFAULT 150,
    EnqueuedAt   DATETIME2 NOT NULL CONSTRAINT DF_PdfRenderQueue_EnqueuedAt DEFAULT SYSUTCDATETIME()
);
GO

-- Failures land here for inspection instead of blocking the queue.
IF OBJECT_ID(N'dbo.PdfRenderDeadLetter', N'U') IS NULL
CREATE TABLE dbo.PdfRenderDeadLetter
(
    DeadLetterId BIGINT IDENTITY(1,1) PRIMARY KEY,
    SourceSchema SYSNAME, SourceTable SYSNAME, KeyColumn SYSNAME, PdfColumn SYSNAME,
    TargetSchema SYSNAME, TargetTable SYSNAME, KeyValue INT, Dpi INT,
    FailedAt     DATETIME2 NOT NULL CONSTRAINT DF_PdfRenderDeadLetter_FailedAt DEFAULT SYSUTCDATETIME(),
    ErrorMessage NVARCHAR(4000)
);
GO

-- ---------------------------------------------------------------------------
-- Drain proc: claim a chunk atomically, render per table-config group with a
-- single batched call, dead-letter anything that fails. Safe to run from
-- multiple workers (READPAST skips rows another drain already claimed).
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.DrainPdfRenderQueue
    @MaxRows INT = 1000
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @claim TABLE
    (
        QueueId BIGINT, SourceSchema SYSNAME, SourceTable SYSNAME, KeyColumn SYSNAME,
        PdfColumn SYSNAME, TargetSchema SYSNAME, TargetTable SYSNAME, KeyValue INT, Dpi INT
    );

    -- Atomically dequeue up to @MaxRows (delete + capture in one statement).
    ;WITH c AS (
        SELECT TOP (@MaxRows) *
        FROM dbo.PdfRenderQueue WITH (READPAST, ROWLOCK)
        ORDER BY QueueId
    )
    DELETE FROM c
    OUTPUT deleted.QueueId, deleted.SourceSchema, deleted.SourceTable, deleted.KeyColumn,
           deleted.PdfColumn, deleted.TargetSchema, deleted.TargetTable, deleted.KeyValue, deleted.Dpi
    INTO @claim;

    IF NOT EXISTS (SELECT 1 FROM @claim) RETURN;

    DECLARE @SourceSchema SYSNAME, @SourceTable SYSNAME, @KeyColumn SYSNAME, @PdfColumn SYSNAME,
            @TargetSchema SYSNAME, @TargetTable SYSNAME, @Dpi INT, @keys NVARCHAR(MAX);

    DECLARE grp CURSOR LOCAL FAST_FORWARD FOR
        SELECT DISTINCT SourceSchema, SourceTable, KeyColumn, PdfColumn, TargetSchema, TargetTable, Dpi
        FROM @claim;

    OPEN grp;
    FETCH NEXT FROM grp INTO @SourceSchema, @SourceTable, @KeyColumn, @PdfColumn, @TargetSchema, @TargetTable, @Dpi;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- NVARCHAR(MAX) convert forces a MAX-typed result so large batches don't truncate.
        SELECT @keys = STRING_AGG(CONVERT(NVARCHAR(MAX), KeyValue), N',')
        FROM @claim
        WHERE SourceSchema = @SourceSchema AND SourceTable = @SourceTable AND KeyColumn = @KeyColumn
          AND PdfColumn = @PdfColumn AND TargetSchema = @TargetSchema AND TargetTable = @TargetTable AND Dpi = @Dpi;

        BEGIN TRY
            EXEC dbo.RenderPdfTableToJpegs
                 @SourceTable  = @SourceTable,  @KeyColumn   = @KeyColumn,
                 @PdfColumn    = @PdfColumn,    @TargetTable = @TargetTable,
                 @SourceSchema = @SourceSchema, @TargetSchema = @TargetSchema,
                 @Dpi = @Dpi, @KeyList = @keys;
        END TRY
        BEGIN CATCH
            INSERT dbo.PdfRenderDeadLetter
                (SourceSchema, SourceTable, KeyColumn, PdfColumn, TargetSchema, TargetTable, KeyValue, Dpi, ErrorMessage)
            SELECT SourceSchema, SourceTable, KeyColumn, PdfColumn, TargetSchema, TargetTable, KeyValue, Dpi, ERROR_MESSAGE()
            FROM @claim
            WHERE SourceSchema = @SourceSchema AND SourceTable = @SourceTable AND KeyColumn = @KeyColumn
              AND PdfColumn = @PdfColumn AND TargetSchema = @TargetSchema AND TargetTable = @TargetTable AND Dpi = @Dpi;
        END CATCH

        FETCH NEXT FROM grp INTO @SourceSchema, @SourceTable, @KeyColumn, @PdfColumn, @TargetSchema, @TargetTable, @Dpi;
    END
    CLOSE grp; DEALLOCATE grp;
END
GO


/* ----- ENQUEUE-ONLY trigger TEMPLATE: copy per source table, replace <...> ---
CREATE OR ALTER TRIGGER dbo.trg_<SourceTable>_EnqueuePdf
ON dbo.<SourceTable>
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(<PdfColumn>) RETURN;

    INSERT dbo.PdfRenderQueue (SourceSchema, SourceTable, KeyColumn, PdfColumn, TargetSchema, TargetTable, KeyValue, Dpi)
    SELECT N'dbo', N'<SourceTable>', N'<KeyColumn>', N'<PdfColumn>', N'dbo', N'<TargetTable>', i.<KeyColumn>, 150
    FROM inserted i
    WHERE i.<PdfColumn> IS NOT NULL;
END
GO
--------------------------------------------------------------------------- */

-- ----- Concrete example: dbo.Documents -> dbo.DocumentsPages ----------------
-- (Drop dbo.trg_Documents_RenderPdf from file 08 first if you installed it;
--  don't run both the synchronous and the enqueue trigger on the same table.)
CREATE OR ALTER TRIGGER dbo.trg_Documents_EnqueuePdf
ON dbo.Documents
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(PdfBytes) RETURN;

    INSERT dbo.PdfRenderQueue (SourceSchema, SourceTable, KeyColumn, PdfColumn, TargetSchema, TargetTable, KeyValue, Dpi)
    SELECT N'dbo', N'Documents', N'DocId', N'PdfBytes', N'dbo', N'DocumentsPages', i.DocId, 150
    FROM inserted i
    WHERE i.PdfBytes IS NOT NULL;
END
GO


/* ============================================================================
   SQL Agent job to drain the queue every minute.
   Run in msdb. Adjust @database_name to your database.
   ============================================================================ */
/*
USE msdb;
GO
EXEC dbo.sp_add_job        @job_name = N'PDF Render Queue Drain', @enabled = 1;
EXEC dbo.sp_add_jobstep    @job_name = N'PDF Render Queue Drain', @step_name = N'Drain',
                           @subsystem = N'TSQL', @database_name = N'YourDatabase',
                           @command = N'EXEC dbo.DrainPdfRenderQueue;';
EXEC dbo.sp_add_schedule   @schedule_name = N'PDF Drain - every minute',
                           @freq_type = 4,            -- daily
                           @freq_interval = 1,
                           @freq_subday_type = 4,     -- minutes
                           @freq_subday_interval = 1; -- every 1 minute
EXEC dbo.sp_attach_schedule @job_name = N'PDF Render Queue Drain', @schedule_name = N'PDF Drain - every minute';
EXEC dbo.sp_add_jobserver  @job_name = N'PDF Render Queue Drain';
GO
*/

-- Manual drain / ad-hoc:  EXEC dbo.DrainPdfRenderQueue;
-- Inspect failures:       SELECT * FROM dbo.PdfRenderDeadLetter ORDER BY FailedAt DESC;
-- Re-queue a dead letter: INSERT dbo.PdfRenderQueue (...) SELECT ... FROM dbo.PdfRenderDeadLetter WHERE ...;
