USE TPOAndreaniGrupo03;
GO

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    -- 1. Datos maestros
    SET IDENTITY_INSERT CLIENTE ON;
    INSERT INTO CLIENTE (IdCliente, Nombre)
    VALUES (401, 'Clinica de Prueba');
    SET IDENTITY_INSERT CLIENTE OFF;

    SET IDENTITY_INSERT MEDICAMENTO ON;
    INSERT INTO MEDICAMENTO
        (IdMedicamento, Nombre, [Descripción], Fabricante, Temperatura_min, Temperatura_max)
    VALUES
        (101, 'Medicamento A', 'Solucion inyectable refrigerada A', 'Laboratorio Alfa', 2.00, 8.00),
        (102, 'Medicamento B', 'Solucion inyectable refrigerada B', 'Laboratorio Beta', 2.00, 8.00);
    SET IDENTITY_INSERT MEDICAMENTO OFF;

    SET IDENTITY_INSERT DEPOSITO ON;
    INSERT INTO DEPOSITO (IdDeposito, Nombre, [Ubicación])
    VALUES
        (301, 'Deposito Central', 'Buenos Aires'),
        (302, 'Deposito Secundario', 'Cordoba');
    SET IDENTITY_INSERT DEPOSITO OFF;

    SET IDENTITY_INSERT LOTE ON;
    INSERT INTO LOTE
        (IdLote, NumeroLote, FechaFabricacion, FechaVencimiento, Estado, IdMedicamento)
    VALUES
        (201, 'ALFA-001', '20260201', '20270630', 'Disponible', 101),
        (202, 'BETA-001', '20260301', '20271231', 'Disponible', 102),
        (203, 'ALFA-002', '20260401', '20270930', 'Disponible', 101),
        (204, 'BETA-002', '20260415', '20280630', 'Disponible', 102),
        (205, 'ALFA-TEST-TRAZA', '20260501', '20281031', 'Disponible', 101);
    SET IDENTITY_INSERT LOTE OFF;

    -- Stock remanente DESPUES de las asignaciones historicas:
    -- lote 201: 8 - 8 = 0; lote 202: 10 - 5 - 4 = 1;
    -- lote 203: 12 - 10 = 2; lote 204: 10 - 5 = 5.
    INSERT INTO EXISTENCIA (IdLote, IdDeposito, CantidadDisponible)
    VALUES
        (201, 301, 0),
        (202, 301, 1),
        (203, 302, 2),
        (204, 301, 5);

    -- 2. Pedidos historicos y uno pendiente para futuras pruebas
    SET IDENTITY_INSERT PEDIDO ON;
    INSERT INTO PEDIDO
        (IdPedido, FechaPedido, Estado, FechaEntregaSolicitada, DireccionDestino, IdCliente)
    VALUES
        (1, '20261101', 'Asignado', '20261105', 'Av. Principal 100, Buenos Aires', 401),
        (3, '20261101', 'Asignado', '20261105', 'Calle Secundaria 200, Buenos Aires', 401),
        (4, '20261101', 'Asignado', '20261105', 'Av. Central 300, Buenos Aires', 401),
        (5, CAST(GETDATE() AS DATE), 'Pendiente', DATEADD(DAY, 30, CAST(GETDATE() AS DATE)),
            'Calle Prueba 400, Buenos Aires', 401);
    SET IDENTITY_INSERT PEDIDO OFF;

    INSERT INTO DETALLE_PEDIDO (IdPedido, IdMedicamento, CantidadSolicitada)
    VALUES
        (1, 101, 10), (1, 102, 5),
        (3, 102, 4),
        (4, 101, 8), (4, 102, 5),
        (5, 101, 2), (5, 102, 4);

    -- 3. Asignaciones y preparaciones historicas
    INSERT INTO ASIGNACION_LOTE
        (IdPedido, IdMedicamento, IdLote, IdDeposito,
         CantidadAsignada, CantidadPreparada, FechaPreparacion, EstadoPreparacion)
    VALUES
        (1, 101, 203, 302, 10, 10, '20261102', 'Validado'),
        (1, 102, 202, 301,  5,  5, '20261102', 'Validado'),
        (3, 102, 202, 301,  4,  3, '20261102', 'Rechazado'),
        (4, 101, 201, 301,  8,  8, '20261102', 'Validado'),
        (4, 102, 204, 301,  5,  5, '20261102', 'Validado');

    -- Cuatro aprobaciones y un rechazo: KPI de error = 20 %.
    SET IDENTITY_INSERT VALIDACION ON;
    INSERT INTO VALIDACION
        (IdValidacion, FechaValidacion, Resultado, ErrorDetectado,
         IdPedido, IdMedicamento, IdLote, IdDeposito)
    VALUES
        (1, '20261102', 'Aprobado', NULL, 1, 101, 203, 302),
        (2, '20261102', 'Aprobado', NULL, 1, 102, 202, 301),
        (3, '20261102', 'Rechazado', 'Cantidad preparada menor a la asignada', 3, 102, 202, 301),
        (4, '20261102', 'Aprobado', NULL, 4, 101, 201, 301),
        (5, '20261102', 'Aprobado', NULL, 4, 102, 204, 301);
    SET IDENTITY_INSERT VALIDACION OFF;

    -- 4. Cajas: capacidad maxima de diez unidades
    SET IDENTITY_INSERT CAJA ON;
    INSERT INTO CAJA (IdCaja, CodigoQR, FechaArmado, Estado, IdPedido)
    VALUES
        (1, 'CAJA-1', '20261102', 'Armada', 1),
        (2, 'CAJA-2', '20261102', 'Armada', 1),
        (3, 'CAJA-3', '20261102', 'Armada', 4),
        (4, 'CAJA-4', '20261102', 'Armada', 4);
    SET IDENTITY_INSERT CAJA OFF;

    INSERT INTO DETALLE_CAJA
        (IdCaja, IdMedicamento, IdLote, IdDeposito, CantidadEmpacada)
    VALUES
        (1, 101, 203, 302, 10),
        (2, 102, 202, 301,  5),
        (3, 101, 201, 301,  8),
        (3, 102, 204, 301,  2),
        (4, 102, 204, 301,  3);

    -- 5. Dos envios: el pedido 4 falla y se entrega en el reintento
    SET IDENTITY_INSERT ENVIO ON;
    INSERT INTO ENVIO
        (IdEnvio, [FechaCreación], Estado, Temperatura_min, Temperatura_max)
    VALUES
        (1, '20261103', 'Preparado', 2.00, 8.00),
        (2, '20261103', 'Preparado', 2.00, 8.00);
    SET IDENTITY_INSERT ENVIO OFF;

    INSERT INTO PEDIDO_ENVIO
        (IdEnvio, IdPedido, FechaPrevista, FechaIntento, Estado, Resultado)
    VALUES
        (1, 1, '20261105', '20261103', 'Entregado', 'Entregado'),
        (1, 4, '20261105', '20261103', 'Fallido',   'Fallido'),
        (2, 4, '20261105', '20261103', 'Entregado', 'Entregado');

    INSERT INTO CAJA_ENVIO
        (IdCaja, IdEnvio, EstadoRecepcion, FechaRecepcion)
    VALUES
        (1, 1, 'Recibida',    '20261103'),
        (2, 1, 'Recibida',    '20261103'),
        (3, 1, 'No recibida', NULL),
        (4, 1, 'No recibida', NULL),
        (3, 2, 'Recibida',    '20261103'),
        (4, 2, 'Recibida',    '20261103');

    COMMIT TRANSACTION;
    PRINT 'Datos iniciales y casos historicos cargados correctamente.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    PRINT ERROR_MESSAGE();
    THROW;
END CATCH;