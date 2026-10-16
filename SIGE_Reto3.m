%% SISTEMA INTELIGENTE DE GESTION ENERGETICA (SIGE)
% Reto 3 - Algoritmo de control y cargas
% Curso: Software para ingenieria - Codigo 203036 - UNAD
%
% OBJETIVO:
% Simular durante 24 horas la generacion hibrida, la demanda comunitaria,
% el estado de carga (SOC) de la bateria y la prioridad de las cargas.
%
% ALCANCE Y SUPUESTOS:
% 1. La guia proporciona la demanda agregada, pero no separa la potencia
%    de la escuela, el bombeo y el alumbrado. Para representar las
%    desconexiones, se supone un reparto de 40%, 35% y 25%, respectivamente.
%    Estos porcentajes son supuestos de modelado, no datos de la guia.
% 2. Se supone una eficiencia de carga/descarga del 100%, porque no se
%    proporciona un valor de eficiencia.
% 3. Cada potencia representa un valor medio constante durante una hora.
% 4. La energia no suministrada se calcula cuando la bateria llega al 0%
%    y aun existe deficit; la escuela se prioriza, pero no se puede atender
%    una carga sin energia disponible.
%
% El archivo funciona como script; no requiere funciones externas.

clc;
clear;
close all;

%% 1. VECTORES HORARIOS DEL RETO 2

horas = 1:24;

% Generacion solar (kW): cero en horas 1-5 y 19-24; maximo de 25 kW
% al mediodia (hora 12).
Pmax_solar = 25;
solar = [0 0 0 0 0 4 8 12 16 20 23 25 ...
         23 20 16 12 8 4 0 0 0 0 0 0];

% Generacion eolica fluctuante (kW), con maximo nominal de 15 kW.
Pmax_eolica = 15;
eolica = [8 11 6 13 9 5 12 7 14 10 8 13 ...
          6 11 9 15 7 12 10 5 13 8 11 6];

% Demanda comunitaria base (kW).
% Horas 1-5 y 22-24: 2-4 kW; horas 6-17: 6-10 kW;
% horas 18-21: 15 kW.
Pmax_demanda = 15;
demanda_base = [3 2 4 3 2 ...
                6 7 8 9 8 10 9 7 8 9 10 8 ...
                15 15 15 15 ...
                3 4 2];

%% 2. VALIDACION DE VECTORES Y LIMITES

assert(numel(horas) == 24 && numel(solar) == 24 && ...
       numel(eolica) == 24 && numel(demanda_base) == 24, ...
       'Error: todos los vectores deben tener 24 elementos.');

assert(max(solar) <= Pmax_solar, ...
       'Error: la generacion solar supera el maximo permitido.');
assert(max(eolica) <= Pmax_eolica, ...
       'Error: la generacion eolica supera el maximo permitido.');
assert(max(demanda_base) <= Pmax_demanda, ...
       'Error: la demanda supera el maximo permitido.');

%% 3. PARAMETROS DE BATERIA Y CONTROL

capacidad_bat = 100;       % Capacidad nominal de la bateria (kWh).
SOC_inicial = 50;          % Estado de carga inicial (%).
SOC_min = 0;               % Limite inferior del SOC (%).
SOC_max = 100;             % Limite superior del SOC (%).
umbral_alerta = 40;        % Umbral de alerta (%).
umbral_emergencia = 20;    % Umbral de emergencia (%).

%% 4. SUPUESTO DE DISTRIBUCION DE LA DEMANDA ENTRE CARGAS

% La guia no proporciona consumos individuales. Cambie estos valores si
% el tutor proporciona las potencias reales de cada servicio.
fraccion_escuela = 0.40;
fraccion_bombeo = 0.35;
fraccion_alumbrado = 0.25;

suma_fracciones = fraccion_escuela + fraccion_bombeo + fraccion_alumbrado;
assert(abs(suma_fracciones - 1) < 1e-10, ...
       'Error: las fracciones de las cargas deben sumar 1.');

demanda_escuela = demanda_base * fraccion_escuela;
demanda_bombeo = demanda_base * fraccion_bombeo;
demanda_alumbrado = demanda_base * fraccion_alumbrado;

%% 5. INICIALIZACION DE VARIABLES

generacion_total = solar + eolica;

balance = zeros(1,24);
SOC_hist = zeros(1,24);
demanda_efectiva = zeros(1,24);
energia_no_suministrada = zeros(1,24);

potencia_escuela_servida = zeros(1,24);
potencia_bombeo_servida = zeros(1,24);
potencia_alumbrado_servida = zeros(1,24);

escuela_activa = false(1,24);
bombeo_activo = false(1,24);
alumbrado_activo = false(1,24);

% Estado de carga expresado en energia almacenada (kWh).
energia_bateria = capacidad_bat * SOC_inicial / 100;

% Estado inicial de los servicios: todos conectados.
estado_escuela = true;
estado_bombeo = true;
estado_alumbrado = true;

%% 6. ENCABEZADO DEL REPORTE

fprintf('\n===============================================================\n');
fprintf(' SIGE - REPORTE DEL ALGORITMO DE CONTROL HORARIO\n');
fprintf('===============================================================\n');
fprintf('Capacidad de bateria: %.1f kWh | SOC inicial: %.1f %%\n', ...
        capacidad_bat, SOC_inicial);
fprintf('Reparto supuesto: escuela 40%%, bombeo 35%%, alumbrado 25%%.\n');
fprintf('Eficiencia de bateria asumida: 100%%.\n\n');

%% 7. SIMULACION DEL CONTROLADOR DURANTE 24 HORAS

for i = 1:24

    % 7.1 Registrar las cargas conectadas al inicio de la hora.
    escuela_activa(i) = estado_escuela;
    bombeo_activo(i) = estado_bombeo;
    alumbrado_activo(i) = estado_alumbrado;

    % 7.2 Calcular potencia demandada por cada carga conectada.
    potencia_escuela_servida(i) = demanda_escuela(i) * double(escuela_activa(i));
    potencia_bombeo_servida(i) = demanda_bombeo(i) * double(bombeo_activo(i));
    potencia_alumbrado_servida(i) = demanda_alumbrado(i) * double(alumbrado_activo(i));

    demanda_efectiva(i) = potencia_escuela_servida(i) + ...
                          potencia_bombeo_servida(i) + ...
                          potencia_alumbrado_servida(i);

    % 7.3 Balance instantaneo de potencia para esta hora.
    balance(i) = generacion_total(i) - demanda_efectiva(i);

    % 7.4 Calcular deficit y excedente de energia del intervalo (kWh).
    if balance(i) >= 0
        excedente_kWh = balance(i) * 1; % Duracion del intervalo: 1 hora.
        deficit_kWh = 0;
    else
        excedente_kWh = 0;
        deficit_kWh = abs(balance(i)) * 1;
    end

    % 7.5 Actualizar la energia de la bateria y registrar energia no servida.
    if excedente_kWh > 0
        energia_bateria = energia_bateria + excedente_kWh;
        energia_bateria = min(energia_bateria, capacidad_bat);
    elseif deficit_kWh > 0
        energia_requerida_bateria = min(deficit_kWh, energia_bateria);
        energia_bateria = energia_bateria - energia_requerida_bateria;
        energia_no_suministrada(i) = deficit_kWh - energia_requerida_bateria;
    end

    % SOC actualizado despues del balance de la hora.
    SOC_actualizado = (energia_bateria / capacidad_bat) * 100;
    SOC_actualizado = min(max(SOC_actualizado, SOC_min), SOC_max);
    SOC_hist(i) = SOC_actualizado;

    % 7.6 Aplicar reglas para el estado de las cargas en la siguiente hora.
    % Si hay superavit/equilibrio, se restablecen todos los servicios.
    % Si hay deficit, se aplica la prioridad segun el SOC actualizado.
    if balance(i) >= 0
        estado_escuela = true;
        estado_bombeo = true;
        estado_alumbrado = true;
    else
        if SOC_actualizado > umbral_alerta
            % Ruta segura: todos los servicios permanecen activos.
            estado_escuela = true;
            estado_bombeo = true;
            estado_alumbrado = true;
        elseif SOC_actualizado > umbral_emergencia
            % Ruta de alerta: se suspende el alumbrado.
            estado_escuela = true;
            estado_bombeo = true;
            estado_alumbrado = false;
        else
            % Ruta de emergencia: se suspende alumbrado y bombeo.
            estado_escuela = true;
            estado_bombeo = false;
            estado_alumbrado = false;
        end
    end

    % 7.7 Reportar los estados vigentes durante la hora calculada.
    if escuela_activa(i)
        texto_escuela = 'ACTIVA';
    else
        texto_escuela = 'SUSPENDIDA';
    end

    if bombeo_activo(i)
        texto_bombeo = 'ACTIVO';
    else
        texto_bombeo = 'SUSPENDIDO';
    end

    if alumbrado_activo(i)
        texto_alumbrado = 'ACTIVO';
    else
        texto_alumbrado = 'SUSPENDIDO';
    end

    fprintf(['Hora %02d | Gen: %5.1f kW | Demanda base: %5.1f kW | ' ...
             'Demanda efectiva: %5.1f kW | Balance: %+6.1f kW | ' ...
             'SOC: %6.2f %% | Escuela: %s | Bombeo: %s | Alumbrado: %s | ' ...
             'Energia no servida: %.2f kWh\n'], ...
             horas(i), generacion_total(i), demanda_base(i), ...
             demanda_efectiva(i), balance(i), SOC_hist(i), ...
             texto_escuela, texto_bombeo, texto_alumbrado, ...
             energia_no_suministrada(i));
end

%% 8. RESUMEN FINAL

fprintf('\n======================= RESUMEN FINAL =========================\n');
fprintf('Generacion solar maxima: %.1f kW.\n', max(solar));
fprintf('Generacion eolica maxima: %.1f kW.\n', max(eolica));
fprintf('Generacion hibrida maxima: %.1f kW.\n', max(generacion_total));
fprintf('Demanda base maxima: %.1f kW.\n', max(demanda_base));
fprintf('Demanda efectiva maxima: %.1f kW.\n', max(demanda_efectiva));
fprintf('SOC final: %.2f %%\n', SOC_hist(end));
fprintf('SOC minimo durante el ciclo: %.2f %%\n', min(SOC_hist));
fprintf('Energia total no suministrada: %.2f kWh\n', sum(energia_no_suministrada));
fprintf('Horas con superavit/equilibrio: %s\n', mat2str(horas(balance >= 0)));
fprintf('Horas con deficit: %s\n', mat2str(horas(balance < 0)));
fprintf('Horas con alumbrado suspendido: %s\n', mat2str(horas(~alumbrado_activo)));
fprintf('Horas con bombeo suspendido: %s\n', mat2str(horas(~bombeo_activo)));
fprintf('===============================================================\n');

%% 9. GRAFICA DE GENERACION Y DEMANDA

figure;
plot(horas, generacion_total, '-ob', 'LineWidth', 1.5);
hold on;
plot(horas, demanda_base, '--k', 'LineWidth', 1.2);
plot(horas, demanda_efectiva, '-sr', 'LineWidth', 1.5);
grid on;
title('Generacion hibrida, demanda base y demanda efectiva');
xlabel('Hora del dia');
ylabel('Potencia (kW)');
legend('Generacion hibrida', 'Demanda base', 'Demanda efectiva', ...
       'Location', 'best');
xlim([1 24]);
set(gca, 'XTick', 1:24);
hold off;

%% 10. GRAFICA DEL ESTADO DE CARGA DE LA BATERIA

figure;
plot(horas, SOC_hist, '-^k', 'LineWidth', 1.5);
hold on;
plot([1 24], [umbral_alerta umbral_alerta], '--r', 'LineWidth', 1.2);
plot([1 24], [umbral_emergencia umbral_emergencia], '--m', 'LineWidth', 1.2);
plot([1 24], [SOC_max SOC_max], ':g', 'LineWidth', 1.2);
grid on;
title('Evolucion horaria del estado de carga de la bateria');
xlabel('Hora del dia');
ylabel('Estado de carga SOC (%)');
legend('SOC de la bateria', 'Umbral de alerta (40%)', ...
       'Umbral de emergencia (20%)', 'SOC maximo (100%)', ...
       'Location', 'best');
xlim([1 24]);
ylim([0 100]);
set(gca, 'XTick', 1:24);
hold off;

%% 11. GRAFICA SEPARADA DEL ESTADO DE LOS SERVICIOS

% Niveles 3, 2 y 1 son posiciones visuales; no representan potencia.
estado_escuela_graf = double(escuela_activa) * 3;
estado_bombeo_graf = double(bombeo_activo) * 2;
estado_alumbrado_graf = double(alumbrado_activo) * 1;

figure;
stairs(horas, estado_escuela_graf, '-b', 'LineWidth', 2);
hold on;
stairs(horas, estado_bombeo_graf, '-r', 'LineWidth', 2);
stairs(horas, estado_alumbrado_graf, '-k', 'LineWidth', 2);
grid on;
title('Estado horario de los servicios del SIGE');
xlabel('Hora del dia');
ylabel('Estado del servicio');
legend('Escuela rural', 'Bombeo agricola', 'Alumbrado publico', ...
       'Location', 'best');
xlim([1 24]);
ylim([0 3.5]);
set(gca, 'XTick', 1:24);
set(gca, 'YTick', [1 2 3]);
set(gca, 'YTickLabel', {'Alumbrado', 'Bombeo', 'Escuela'});
hold off;

%% 12. ALCANCE DEL MODELO
% Las fracciones 40/35/25 son supuestos ilustrativos porque la guia no
% proporciona la potencia individual de cada carga.
% La energia no suministrada se reporta si la bateria se agota. En ese
% caso la escuela sigue siendo la carga prioritaria, pero el modelo no
% puede garantizar suministro fisico sin energia disponible.
% Este script no modifica los vectores originales del Reto 2.
