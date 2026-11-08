USE TPOAndreaniGrupo03
GO

CREATE VIEW vw_KPI_EntregasATiempo
AS
SELECT
    COUNT(*) AS PedidosEvaluados,

    SUM(CASE
        WHEN EstadoCumplimiento = 'A tiempo' THEN 1
        ELSE 0
    END) AS PedidosATiempo,

    CAST(
        100.0 * SUM(CASE
            WHEN EstadoCumplimiento = 'A tiempo' THEN 1
            ELSE 0
        END) / NULLIF(COUNT(*), 0)
        AS DECIMAL(5,2)
    ) AS PorcentajeEntregasATiempo

FROM (
    SELECT
        P.IdPedido,

        CASE
            WHEN E.FechaEntregaReal IS NOT NULL
                 AND E.FechaEntregaReal <= P.FechaEntregaSolicitada
                THEN 'A tiempo'

            WHEN E.FechaEntregaReal IS NOT NULL
                THEN 'Fuera de tiempo'

            WHEN P.FechaEntregaSolicitada < CAST(GETDATE() AS DATE)
                THEN 'Fuera de tiempo'

            ELSE 'Pendiente'
        END AS EstadoCumplimiento

    FROM PEDIDO P

    LEFT JOIN (
        SELECT
            IdPedido,
            MIN(FechaIntento) AS FechaEntregaReal
        FROM PEDIDO_ENVIO
        WHERE Resultado = 'Entregado'
        GROUP BY IdPedido
    ) E
        ON P.IdPedido = E.IdPedido
) AS PedidosClasificados

WHERE EstadoCumplimiento <> 'Pendiente';
GO

CREATE VIEW vw_KPI_ErroresPreparacion
AS
SELECT
    COUNT(*) AS TotalValidaciones,

    SUM(CASE
        WHEN Resultado = 'Aprobado' THEN 1
        ELSE 0
    END) AS ValidacionesAprobadas,

    SUM(CASE
        WHEN Resultado = 'Rechazado' THEN 1
        ELSE 0
    END) AS ValidacionesRechazadas,

    CAST(
        100.0 * SUM(CASE
            WHEN Resultado = 'Rechazado' THEN 1
            ELSE 0
        END) / NULLIF(COUNT(*), 0)
        AS DECIMAL(5,2)
    ) AS PorcentajeErrores

FROM VALIDACION;
GO

CREATE VIEW vw_KPI_IntentosEntrega
AS
SELECT
    COUNT(*) AS PedidosEntregados,
    SUM(CantidadIntentos) AS TotalIntentos,
    CAST(
        AVG(CAST(CantidadIntentos AS DECIMAL(10,2)))
        AS DECIMAL(10,2)
    ) AS PromedioIntentos
FROM (
    SELECT
        PE.IdPedido,
        COUNT(*) AS CantidadIntentos
    FROM PEDIDO_ENVIO PE
    WHERE PE.FechaIntento IS NOT NULL
      AND EXISTS (
          SELECT 1
          FROM PEDIDO_ENVIO PE2
          WHERE PE2.IdPedido = PE.IdPedido
            AND PE2.Resultado = 'Entregado'
      )
    GROUP BY PE.IdPedido
) AS IntentosPorPedido;
GO