USE TPOAndreaniGrupo03;
GO

CREATE PROCEDURE sp_AsignarLotesPedido
    @IdPedido INT
AS
BEGIN
    DECLARE @IdMedicamento INT;
    DECLARE @CantidadSolicitada INT;
    DECLARE @IdLote INT;
    DECLARE @IdDeposito INT;
    DECLARE @AsignacionCompleta INT;

    SET @AsignacionCompleta = 1;

    -- Verificar que el pedido exista y este pendiente
    IF NOT EXISTS (
        SELECT 1
        FROM PEDIDO
        WHERE IdPedido = @IdPedido
          AND Estado = 'Pendiente'
    )
    BEGIN
        PRINT 'El pedido no existe o no esta pendiente.';
        RETURN;
    END;

    -- Verificar que tenga medicamentos solicitados
    IF NOT EXISTS (
        SELECT 1
        FROM DETALLE_PEDIDO
        WHERE IdPedido = @IdPedido
    )
    BEGIN
        PRINT 'El pedido no tiene medicamentos.';
        RETURN;
    END;

    -- Evitar asignar dos veces el mismo pedido
    IF EXISTS (
        SELECT 1
        FROM ASIGNACION_LOTE
        WHERE IdPedido = @IdPedido
    )
    BEGIN
        PRINT 'El pedido ya tiene lotes asignados.';
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE cursor_medicamentos CURSOR FOR
        SELECT IdMedicamento, CantidadSolicitada
        FROM DETALLE_PEDIDO
        WHERE IdPedido = @IdPedido;

        OPEN cursor_medicamentos;

        FETCH NEXT FROM cursor_medicamentos
        INTO @IdMedicamento, @CantidadSolicitada;

        WHILE @@FETCH_STATUS = 0
          AND @AsignacionCompleta = 1
        BEGIN
            SET @IdLote = NULL;
            SET @IdDeposito = NULL;

            -- Seleccionar el lote mediante FEFO simplificado
            SELECT TOP 1
                @IdLote = L.IdLote,
                @IdDeposito = E.IdDeposito
            FROM LOTE L
            INNER JOIN EXISTENCIA E
                ON L.IdLote = E.IdLote
            WHERE L.IdMedicamento = @IdMedicamento
              AND L.Estado = 'Disponible'
              AND L.FechaVencimiento > CAST(GETDATE() AS DATE)
              AND E.CantidadDisponible >= @CantidadSolicitada
            ORDER BY
                L.FechaVencimiento ASC,
                L.IdLote ASC,
                E.IdDeposito ASC;

            IF @IdLote IS NULL
            BEGIN
                SET @AsignacionCompleta = 0;
            END
            ELSE
            BEGIN
                -- Descontar la cantidad asignada
                UPDATE EXISTENCIA
                SET CantidadDisponible =
                    CantidadDisponible - @CantidadSolicitada
                WHERE IdLote = @IdLote
                  AND IdDeposito = @IdDeposito
                  AND CantidadDisponible >= @CantidadSolicitada;

                -- Verificar que el descuento se haya realizado
                IF @@ROWCOUNT = 0
                BEGIN
                    SET @AsignacionCompleta = 0;
                END
                ELSE
                BEGIN
                    INSERT INTO ASIGNACION_LOTE
                        (IdPedido, IdMedicamento, IdLote,
                         IdDeposito, CantidadAsignada,
                         CantidadPreparada, FechaPreparacion,
                         EstadoPreparacion)
                    VALUES
                        (@IdPedido, @IdMedicamento, @IdLote,
                         @IdDeposito, @CantidadSolicitada,
                         0, NULL, 'Asignado');
                END;
            END;

            FETCH NEXT FROM cursor_medicamentos
            INTO @IdMedicamento, @CantidadSolicitada;
        END;

        CLOSE cursor_medicamentos;
        DEALLOCATE cursor_medicamentos;

        IF @AsignacionCompleta = 0
        BEGIN
            ROLLBACK TRANSACTION;
            PRINT 'Stock insuficiente para completar el pedido.';
            RETURN;
        END;

        UPDATE PEDIDO
        SET Estado = 'Asignado'
        WHERE IdPedido = @IdPedido
          AND Estado = 'Pendiente';

        IF @@ROWCOUNT = 0
        BEGIN
            ROLLBACK TRANSACTION;
            PRINT 'No se pudo confirmar el pedido.';
            RETURN;
        END;

        COMMIT TRANSACTION;
        PRINT 'Pedido asignado correctamente.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        PRINT ERROR_MESSAGE();
    END CATCH;
END;
GO

CREATE PROCEDURE sp_RegistrarPreparacion
    @IdPedido INT,
    @IdMedicamento INT,
    @IdLote INT,
    @IdDeposito INT,
    @CantidadPreparada INT
AS
BEGIN
    -- Verificar que exista una asignacion pendiente de preparacion
    IF NOT EXISTS (
        SELECT 1
        FROM ASIGNACION_LOTE
        WHERE IdPedido = @IdPedido
          AND IdMedicamento = @IdMedicamento
          AND IdLote = @IdLote
          AND IdDeposito = @IdDeposito
          AND EstadoPreparacion = 'Asignado'
    )
    BEGIN
        PRINT 'La asignacion no existe o ya fue preparada.';
        RETURN;
    END;

    -- Verificar que la cantidad sea valida
    IF @CantidadPreparada IS NULL OR @CantidadPreparada <= 0
    BEGIN
        PRINT 'La cantidad preparada debe ser mayor que cero.';
        RETURN;
    END;

    -- Registrar la preparacion
    UPDATE ASIGNACION_LOTE
    SET CantidadPreparada = @CantidadPreparada,
        FechaPreparacion = CAST(GETDATE() AS DATE),
        EstadoPreparacion = 'Preparado'
    WHERE IdPedido = @IdPedido
      AND IdMedicamento = @IdMedicamento
      AND IdLote = @IdLote
      AND IdDeposito = @IdDeposito
      AND EstadoPreparacion = 'Asignado'
      AND CantidadAsignada >= @CantidadPreparada;

    IF @@ROWCOUNT = 0
    BEGIN
        PRINT 'No se pudo registrar la preparacion. Verifique la cantidad y el estado.';
        RETURN;
    END;

    PRINT 'Preparacion registrada correctamente.';
END;
GO

CREATE PROCEDURE sp_ValidarPreparacion
    @IdPedido INT,
    @IdMedicamento INT,
    @IdLote INT,
    @IdDeposito INT,
    @Resultado VARCHAR(30),
    @ErrorDetectado VARCHAR(500) = NULL
AS
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM ASIGNACION_LOTE
        WHERE IdPedido = @IdPedido
          AND IdMedicamento = @IdMedicamento
          AND IdLote = @IdLote
          AND IdDeposito = @IdDeposito
          AND EstadoPreparacion = 'Preparado'
    )
    BEGIN
        PRINT 'La preparacion no existe o no esta pendiente de validacion.';
        RETURN;
    END;

    IF @Resultado NOT IN ('Aprobado', 'Rechazado')
       OR @Resultado IS NULL
    BEGIN
        PRINT 'El resultado debe ser Aprobado o Rechazado.';
        RETURN;
    END;

    IF @Resultado = 'Aprobado'
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM ASIGNACION_LOTE
            WHERE IdPedido = @IdPedido
              AND IdMedicamento = @IdMedicamento
              AND IdLote = @IdLote
              AND IdDeposito = @IdDeposito
              AND CantidadPreparada = CantidadAsignada
        )
        BEGIN
            PRINT 'No se puede aprobar una preparacion incompleta.';
            RETURN;
        END;
    END;

    IF @Resultado = 'Rechazado'
       AND (@ErrorDetectado IS NULL OR @ErrorDetectado = '')
    BEGIN
        PRINT 'Debe indicar el error detectado.';
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO VALIDACION
            (FechaValidacion, Resultado, ErrorDetectado,
             IdPedido, IdMedicamento, IdLote, IdDeposito)
        VALUES
            (CAST(GETDATE() AS DATE), @Resultado, @ErrorDetectado,
             @IdPedido, @IdMedicamento, @IdLote, @IdDeposito);

        UPDATE ASIGNACION_LOTE
        SET EstadoPreparacion =
            CASE
                WHEN @Resultado = 'Aprobado' THEN 'Validado'
                ELSE 'Rechazado'
            END
        WHERE IdPedido = @IdPedido
          AND IdMedicamento = @IdMedicamento
          AND IdLote = @IdLote
          AND IdDeposito = @IdDeposito
          AND EstadoPreparacion = 'Preparado';

        IF @@ROWCOUNT = 0
        BEGIN
            ROLLBACK TRANSACTION;
            PRINT 'No se pudo actualizar la preparacion.';
            RETURN;
        END;

        COMMIT TRANSACTION;
        PRINT 'Validacion registrada correctamente.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        PRINT ERROR_MESSAGE();
    END CATCH;
END;
GO

CREATE PROCEDURE sp_ArmarCajasPedido
    @IdPedido INT
AS
BEGIN
    DECLARE @IdMedicamento INT;
    DECLARE @IdLote INT;
    DECLARE @IdDeposito INT;
    DECLARE @CantidadPreparada INT;
    DECLARE @CantidadRestante INT;
    DECLARE @CantidadEmpacar INT;
    DECLARE @IdCaja INT;
    DECLARE @EspacioDisponible INT;

    -- Comprobar que el pedido exista
    IF NOT EXISTS (
        SELECT 1
        FROM PEDIDO
        WHERE IdPedido = @IdPedido
          AND Estado = 'Asignado'
    )
    BEGIN
        PRINT 'El pedido no existe o no esta asignado.';
        RETURN;
    END;

    -- Comprobar que existan asignaciones
    IF NOT EXISTS (
        SELECT 1
        FROM ASIGNACION_LOTE
        WHERE IdPedido = @IdPedido
    )
    BEGIN
        PRINT 'El pedido no tiene lotes asignados.';
        RETURN;
    END;

    -- Comprobar que todas las asignaciones esten validadas
    IF EXISTS (
        SELECT 1
        FROM ASIGNACION_LOTE
        WHERE IdPedido = @IdPedido
          AND (
              EstadoPreparacion <> 'Validado'
              OR CantidadPreparada <> CantidadAsignada
          )
    )
    BEGIN
        PRINT 'El pedido tiene preparaciones sin validar.';
        RETURN;
    END;

    -- Comprobar que se cubran todas las cantidades solicitadas
    IF EXISTS (
        SELECT 1
        FROM DETALLE_PEDIDO D
        WHERE D.IdPedido = @IdPedido
          AND D.CantidadSolicitada <> (
              SELECT ISNULL(SUM(A.CantidadPreparada), 0)
              FROM ASIGNACION_LOTE A
              WHERE A.IdPedido = D.IdPedido
                AND A.IdMedicamento = D.IdMedicamento
          )
    )
    BEGIN
        PRINT 'El pedido no tiene todas sus cantidades preparadas.';
        RETURN;
    END;

    -- Evitar armar dos veces las cajas del mismo pedido
    IF EXISTS (
        SELECT 1
        FROM CAJA
        WHERE IdPedido = @IdPedido
    )
    BEGIN
        PRINT 'El pedido ya tiene cajas.';
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        SET @EspacioDisponible = 0;

        DECLARE cursor_cajas CURSOR LOCAL FOR
        SELECT
            IdMedicamento,
            IdLote,
            IdDeposito,
            CantidadPreparada
        FROM ASIGNACION_LOTE
        WHERE IdPedido = @IdPedido
        ORDER BY IdMedicamento, IdLote, IdDeposito;

        OPEN cursor_cajas;

        FETCH NEXT FROM cursor_cajas
        INTO @IdMedicamento, @IdLote,
             @IdDeposito, @CantidadPreparada;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @CantidadRestante = @CantidadPreparada;

            WHILE @CantidadRestante > 0
            BEGIN
                -- Crear una caja si no queda espacio
                IF @EspacioDisponible = 0
                BEGIN
                    INSERT INTO CAJA
                        (CodigoQR, FechaArmado, Estado, IdPedido)
                    VALUES
                        ('TEMP-' + CAST(@IdPedido AS VARCHAR(20)),
                         CAST(GETDATE() AS DATE),
                         'Armada', @IdPedido);

                    SET @IdCaja = CAST(@@IDENTITY AS INT);

                    UPDATE CAJA
                    SET CodigoQR =
                        'CAJA-' + CAST(@IdCaja AS VARCHAR(20))
                    WHERE IdCaja = @IdCaja;

                    SET @EspacioDisponible = 10;
                END;

                -- Determinar cuantas unidades entran
                IF @CantidadRestante <= @EspacioDisponible
                    SET @CantidadEmpacar = @CantidadRestante;
                ELSE
                    SET @CantidadEmpacar = @EspacioDisponible;

                -- Registrar el contenido de la caja
                INSERT INTO DETALLE_CAJA
                    (IdCaja, IdMedicamento, IdLote,
                     IdDeposito, CantidadEmpacada)
                VALUES
                    (@IdCaja, @IdMedicamento, @IdLote,
                     @IdDeposito, @CantidadEmpacar);

                SET @CantidadRestante =
                    @CantidadRestante - @CantidadEmpacar;

                SET @EspacioDisponible =
                    @EspacioDisponible - @CantidadEmpacar;
            END;

            FETCH NEXT FROM cursor_cajas
            INTO @IdMedicamento, @IdLote,
                 @IdDeposito, @CantidadPreparada;
        END;

        CLOSE cursor_cajas;
        DEALLOCATE cursor_cajas;

        COMMIT TRANSACTION;
        PRINT 'Cajas armadas correctamente.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        PRINT ERROR_MESSAGE();
    END CATCH;
END;
GO

CREATE PROCEDURE sp_ArmarEnvioAutomatico
AS
BEGIN
    DECLARE @IdPedido INT;
    DECLARE @FechaPrevista DATE;
    DECLARE @CantidadCajas INT;
    DECLARE @EspacioDisponible INT;
    DECLARE @IdEnvio INT;

    DECLARE @TempPedidoMin DECIMAL(5,2);
    DECLARE @TempPedidoMax DECIMAL(5,2);
    DECLARE @TempEnvioMin DECIMAL(5,2);
    DECLARE @TempEnvioMax DECIMAL(5,2);

    SET @EspacioDisponible = 10;
    SET @IdEnvio = NULL;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE cursor_envios CURSOR LOCAL FOR
        SELECT
            P.IdPedido,
            P.FechaEntregaSolicitada,
            COUNT(DISTINCT C.IdCaja),
            MAX(M.Temperatura_min),
            MIN(M.Temperatura_max)
        FROM PEDIDO P
        INNER JOIN CAJA C
            ON P.IdPedido = C.IdPedido
        INNER JOIN DETALLE_PEDIDO D
            ON P.IdPedido = D.IdPedido
        INNER JOIN MEDICAMENTO M
            ON D.IdMedicamento = M.IdMedicamento
        WHERE P.Estado = 'Asignado'
          -- No incluir pedidos ya asociados a un envio
          AND NOT EXISTS (
            SELECT 1
            FROM PEDIDO_ENVIO PE
            WHERE PE.IdPedido = P.IdPedido
              AND PE.Estado <> 'Fallido'
          )

          -- No incluir preparaciones pendientes o rechazadas
          AND NOT EXISTS (
              SELECT 1
              FROM ASIGNACION_LOTE A
              WHERE A.IdPedido = P.IdPedido
                AND (
                    A.EstadoPreparacion <> 'Validado'
                    OR A.CantidadPreparada <> A.CantidadAsignada
                )
          )

          -- Todas las cantidades deben estar empacadas
          AND NOT EXISTS (
              SELECT 1
              FROM DETALLE_PEDIDO DP
              WHERE DP.IdPedido = P.IdPedido
                AND DP.CantidadSolicitada <> (
                    SELECT ISNULL(SUM(DC.CantidadEmpacada), 0)
                    FROM CAJA C2
                    INNER JOIN DETALLE_CAJA DC
                        ON C2.IdCaja = DC.IdCaja
                    WHERE C2.IdPedido = P.IdPedido
                      AND DC.IdMedicamento = DP.IdMedicamento
                )
          )

        GROUP BY P.IdPedido, P.FechaEntregaSolicitada
        HAVING COUNT(DISTINCT C.IdCaja) <= 10
           AND MAX(M.Temperatura_min) <= MIN(M.Temperatura_max)
        ORDER BY P.IdPedido;

        OPEN cursor_envios;

        FETCH NEXT FROM cursor_envios
        INTO @IdPedido, @FechaPrevista, @CantidadCajas,
             @TempPedidoMin, @TempPedidoMax;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Comprobar capacidad
            IF @CantidadCajas <= @EspacioDisponible
            BEGIN
                -- Primer pedido: crear el envio
                IF @IdEnvio IS NULL
                BEGIN
                    INSERT INTO ENVIO
                        ([FechaCreación], Estado,
                         Temperatura_min, Temperatura_max)
                    VALUES
                        (CAST(GETDATE() AS DATE),
                         'Preparado',
                         @TempPedidoMin, @TempPedidoMax);

                    SET @IdEnvio = CAST(@@IDENTITY AS INT);

                    SET @TempEnvioMin = @TempPedidoMin;
                    SET @TempEnvioMax = @TempPedidoMax;
                END;

                -- Comprobar compatibilidad de temperatura
                IF @TempPedidoMin <= @TempEnvioMax
                   AND @TempPedidoMax >= @TempEnvioMin
                BEGIN
                    -- Asociar el pedido al envio
                    INSERT INTO PEDIDO_ENVIO
                        (IdEnvio, IdPedido, FechaPrevista,
                         FechaIntento, Estado, Resultado)
                    VALUES
                        (@IdEnvio, @IdPedido, @FechaPrevista,
                         NULL, 'Pendiente', NULL);

                    -- Asociar todas las cajas del pedido
                    INSERT INTO CAJA_ENVIO
                        (IdCaja, IdEnvio,
                         EstadoRecepcion, FechaRecepcion)
                    SELECT
                        IdCaja, @IdEnvio, 'Pendiente', NULL
                    FROM CAJA
                    WHERE IdPedido = @IdPedido;

                    -- Actualizar espacio disponible
                    SET @EspacioDisponible =
                        @EspacioDisponible - @CantidadCajas;

                    -- Actualizar intervalo termico del envio
                    IF @TempPedidoMin > @TempEnvioMin
                        SET @TempEnvioMin = @TempPedidoMin;

                    IF @TempPedidoMax < @TempEnvioMax
                        SET @TempEnvioMax = @TempPedidoMax;

                    UPDATE ENVIO
                    SET Temperatura_min = @TempEnvioMin,
                        Temperatura_max = @TempEnvioMax
                    WHERE IdEnvio = @IdEnvio;
                END;
            END;

            FETCH NEXT FROM cursor_envios
            INTO @IdPedido, @FechaPrevista, @CantidadCajas,
                 @TempPedidoMin, @TempPedidoMax;
        END;

        CLOSE cursor_envios;
        DEALLOCATE cursor_envios;

        COMMIT TRANSACTION;

        IF @IdEnvio IS NULL
            PRINT 'No hay pedidos disponibles para armar un envio.';
        ELSE
            PRINT 'Envio armado correctamente.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        PRINT ERROR_MESSAGE();
    END CATCH;
END;
GO

CREATE PROCEDURE sp_RegistrarResultadoEntrega
    @IdEnvio INT,
    @IdPedido INT,
    @Resultado VARCHAR(30)
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Comprobar que el pedido pertenece al envío
        IF NOT EXISTS (
            SELECT 1
            FROM PEDIDO_ENVIO
            WHERE IdEnvio = @IdEnvio
              AND IdPedido = @IdPedido
        )
        BEGIN
            PRINT 'El pedido no pertenece al envio.';
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        -- Comprobar que todavía está pendiente
        IF NOT EXISTS (
            SELECT 1
            FROM PEDIDO_ENVIO
            WHERE IdEnvio = @IdEnvio
              AND IdPedido = @IdPedido
              AND Estado = 'Pendiente'
        )
        BEGIN
            PRINT 'El pedido ya tiene un resultado registrado.';
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        -- Comprobar resultado válido
        IF @Resultado NOT IN ('Entregado', 'Fallido')
           OR @Resultado IS NULL
        BEGIN
            PRINT 'Resultado de entrega no valido.';
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        -- Actualizar resultado del pedido
        UPDATE PEDIDO_ENVIO
        SET
            FechaIntento = CAST(GETDATE() AS DATE),
            Estado = @Resultado,
            Resultado = @Resultado
        WHERE IdEnvio = @IdEnvio
          AND IdPedido = @IdPedido;

        -- Actualizar solamente las cajas de ese pedido
        UPDATE CE
        SET
            CE.EstadoRecepcion =
                CASE
                    WHEN @Resultado = 'Entregado'
                        THEN 'Recibida'
                    ELSE 'No recibida'
                END,
            CE.FechaRecepcion =
                CASE
                    WHEN @Resultado = 'Entregado'
                        THEN CAST(GETDATE() AS DATE)
                    ELSE NULL
                END
        FROM CAJA_ENVIO CE
        INNER JOIN CAJA C
            ON CE.IdCaja = C.IdCaja
        WHERE CE.IdEnvio = @IdEnvio
          AND C.IdPedido = @IdPedido;

        COMMIT TRANSACTION;

        PRINT 'Resultado de entrega registrado correctamente.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        PRINT ERROR_MESSAGE();
    END CATCH;
END;
GO

CREATE PROCEDURE sp_ConsultarTrazabilidadLote
    @IdLote INT
AS
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM LOTE
        WHERE IdLote = @IdLote
    )
    BEGIN
        PRINT 'El lote indicado no existe.';
        RETURN;
    END;

    SELECT
        L.IdLote,
        L.NumeroLote,
        L.IdMedicamento,
        A.IdPedido,
        A.IdDeposito,
        A.CantidadAsignada,
        A.CantidadPreparada,
        A.EstadoPreparacion,
        C.IdCaja,
        C.CodigoQR,
        C.CantidadEmpacada,
        CE.IdEnvio,
        PE.FechaIntento,
        PE.Estado AS EstadoEntrega,
        PE.Resultado,
        CE.EstadoRecepcion

    FROM LOTE L

    LEFT JOIN ASIGNACION_LOTE A
        ON L.IdLote = A.IdLote

    LEFT JOIN (
        SELECT
            CA.IdPedido,
            CA.IdCaja,
            CA.CodigoQR,
            DC.IdMedicamento,
            DC.IdLote,
            DC.IdDeposito,
            DC.CantidadEmpacada
        FROM CAJA CA
        INNER JOIN DETALLE_CAJA DC
            ON CA.IdCaja = DC.IdCaja
    ) C
        ON A.IdPedido = C.IdPedido
       AND A.IdMedicamento = C.IdMedicamento
       AND A.IdLote = C.IdLote
       AND A.IdDeposito = C.IdDeposito

    LEFT JOIN CAJA_ENVIO CE
        ON C.IdCaja = CE.IdCaja

    LEFT JOIN PEDIDO_ENVIO PE
        ON CE.IdEnvio = PE.IdEnvio
       AND A.IdPedido = PE.IdPedido

    WHERE L.IdLote = @IdLote
    ORDER BY A.IdPedido, CE.IdEnvio, C.IdCaja;
END;
GO